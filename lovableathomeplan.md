# Apothecary → "Lovable for Phoenix LiveView" Platform Design

## Context
Apothecary is already a working AI orchestrator with multi-project support, per-project brewer pools, DevServer previews (localhost:port), and worktree management. The goal is to evolve it into a platform where a user gets a VM, creates Phoenix LiveView projects, and AI agents build them with live production domains and branch previews.

**Confirmed decisions:**
- **Single-user VM** — no auth complexity, everything runs directly on the host
- **Multi-project** — one Apothecary instance manages many projects
- **Separate processes + Caddy** — each project is a standard Phoenix app running as its own OS process, Caddy handles routing/SSL
- **Ecto/Postgres for user projects** — agents know Ecto, migrations work, single Postgres instance on the host
- **Mnesia stays for Apothecary** — orchestration state, no changes. Postgres is ONLY for user project apps, never for Apothecary itself
- **Git: support both modes** — GitHub PRs (review) and local auto-merge (rapid iteration), per-project setting
- **Platform subdomains** — `{slug}.{platform-domain}` for prod, `{branch}--{slug}.{platform-domain}` for previews
- **No Docker** — everything runs directly on the VM as system services
- **Platform mode is opt-in** — all deploy/release infrastructure is behind a config flag so Apothecary works exactly as before when used locally without deploy features

---

## Platform Mode vs Local Mode

Apothecary has two modes of operation:

**Local mode** (default, current behavior):
- Orchestrates agents, manages worktrees, DevServer previews on localhost ports
- No Caddy, no production servers, no project databases
- Nothing changes from how Apothecary works today

**Platform mode** (activated by setting `PLATFORM_DOMAIN`):
- All local mode features PLUS:
- ProductionServer, CaddyManager, ProjectDatabase start up
- Projects get live domains, branch previews get subdomains
- Worktree deletion cleans up temporary databases

**Implementation:**
```elixir
# config/runtime.exs
if platform_domain = System.get_env("PLATFORM_DOMAIN") do
  config :apothecary, :platform_mode, true
  config :apothecary, :platform_domain, platform_domain
end

# application.ex
children = [
  # ... existing children always start ...
] ++ platform_children()

defp platform_children do
  if Application.get_env(:apothecary, :platform_mode) do
    [Apothecary.ProductionServer, Apothecary.CaddyManager]
  else
    []
  end
end
```

**Integration hooks guard on the flag:**
```elixir
# In WorktreeManager, DevServer, etc.
if Apothecary.platform_mode?() do
  ProjectDatabase.drop_branch_database(slug, branch)
end
```

**Dashboard conditionally renders deploy controls:**
```elixir
<%= if Apothecary.platform_mode?() do %>
  <.production_controls project={@project} />
<% end %>
```

---

## One-Line Setup Script

```bash
curl -sSL https://raw.githubusercontent.com/.../setup.sh | bash -s -- myapp.example.com
```

**What the script does:**
1. Install system deps (Elixir, Erlang, Node, Postgres, Caddy, git, Claude CLI)
2. Configure Postgres (local socket auth, create apothecary role)
3. Configure Caddy with wildcard SSL for `*.{domain}`
4. Clone and build Apothecary (`mix deps.get && mix compile`)
5. Set up systemd services:
   - `apothecary.service` — runs Apothecary with `PLATFORM_DOMAIN={domain}`
   - Caddy and Postgres already have their own systemd units
6. Start everything

**Changing the domain later:**
```bash
# Edit the systemd env file and restart
sudo sed -i 's/PLATFORM_DOMAIN=.*/PLATFORM_DOMAIN=newdomain.com/' /etc/apothecary/env
sudo systemctl restart apothecary
# Caddy config also updated (script provides a helper or Apothecary does it on boot)
```

**DNS requirement (manual):** User points `*.myapp.example.com` as a wildcard A record to the VM's IP.

---

## Deployment Model

```
VM (single user)
├── Apothecary          (port 4005, orchestrator + dashboard)
├── Caddy               (system service, port 80/443, wildcard SSL, routes by hostname)
├── Postgres            (system service, port 5432, one DB per project + per branch)
├── Project A           (port 10001, MIX_ENV=prod mix phx.server)
├── Project B           (port 10002, MIX_ENV=prod mix phx.server)
└── Directories
    ├── Mnesia dir      (Apothecary state, configured in config)
    └── /projects       (project source code + worktrees)
```

**Postgres databases per project:**
- `{slug}_prod` — production database (main branch)
- `{slug}_{branch}` — temporary database per worktree/preview (cleaned up on worktree deletion)

**Caddy routing:**
- `app.{domain}` → `localhost:4005` (Apothecary dashboard)
- `{slug}.{domain}` → `localhost:{prod_port}` (production, main branch)
- `{branch}--{slug}.{domain}` → `localhost:{preview_port}` (preview, feature branch)

---

## New Modules

### 1. `Apothecary.ProductionServer` (GenServer) — platform mode only

Follows `DevServer` pattern — Erlang Port process management, health checks, PubSub.

**Process management:** Spawns `MIX_ENV=prod mix phx.server` as an Erlang Port.
- Monitors OS process, auto-restarts on crash
- Streams last N lines of output to dashboard via PubSub (`"production:updates"`)
- On Apothecary restart: reads saved state from Mnesia, re-spawns all production servers

**API:**
- `start_production(project_id)` — `mix deps.get → mix ecto.migrate → mix phx.server`
- `stop_production(project_id)` — SIGTERM → timeout → SIGKILL
- `rebuild(project_id)` — `git pull → stop → deps.get → ecto.migrate → start`
- `get_status(project_id)` — `:running | :stopped | :starting | :error`

**Port allocation:** `10000 + :erlang.phash2(project_id, 5000)` (range 10000-14999)

**Environment injected via Port:**
```
MIX_ENV=prod
PORT={allocated_port}
PHX_HOST={slug}.{platform-domain}
DATABASE_URL=ecto://localhost/{slug}_prod
SECRET_KEY_BASE={generated_key}
PHX_SERVER=true
```

**State persisted to Mnesia** (new table `apothecary_production_servers`) for crash recovery.

### 2. `Apothecary.CaddyManager` (GenServer) — platform mode only

Manages Caddy routes via its admin REST API (`localhost:2019/config/`).

- `add_route(subdomain, target_port)` — adds reverse_proxy route
- `remove_route(subdomain)` — removes route
- On init: syncs routes from running projects/previews
- Called by DevServer (preview start/stop) and ProductionServer (deploy)

### 3. `Apothecary.ProjectDatabase` (module) — platform mode only

Manages Postgres databases for **user projects only** (not Apothecary — that stays Mnesia).

- `create_database(slug, env)` — `CREATE DATABASE {slug}_prod` or `{slug}_{branch}`
- `drop_database(slug, env)` — `DROP DATABASE`
- `drop_branch_database(slug, branch)` — cleanup for worktree deletion
- `run_migrations(project_path, database_url)` — `mix ecto.migrate` in project dir
- `database_url(slug, env)` — constructs connection string

### 4. `Apothecary.ProjectEnv` (module) — platform mode only

Generates per-project environment variable maps:
- `SECRET_KEY_BASE` — auto-generated on project creation
- `DATABASE_URL` — constructed from slug
- `PHX_HOST` — `{slug}.{platform-domain}`
- `PORT` — from port allocation

### 5. `Apothecary.platform_mode?/0` (helper)

Simple check used throughout the codebase to guard platform-only code paths:
```elixir
def platform_mode?, do: Application.get_env(:apothecary, :platform_mode, false)
```

---

## Integration Points

All platform integration points are guarded by `Apothecary.platform_mode?()` — they are no-ops in local mode.

1. **Bootstrapper → ProjectDatabase**: After scaffolding, create Postgres DB + `mix ecto.create`
2. **DevServer → CaddyManager**: On preview start → `add_route`; on stop → `remove_route`
3. **DevServer → ProjectDatabase**: On preview start → `create_database(slug, branch)`; creates per-branch DB
4. **PRMonitor (on MERGED) → ProductionServer**: Merge detected → `rebuild(project_id)`
5. **Brewer (local-merge mode) → ProductionServer**: Local merge → `rebuild`
6. **ProductionServer → CaddyManager**: First deploy → `add_route("{slug}", port)`
7. **WorktreeManager → ProjectDatabase**: On worktree deletion → `drop_branch_database(slug, branch)` (cleanup temp DBs)
8. **Project struct**: Extend with `domain_slug`, `secret_key_base`, `production_port`

---

## Files to Modify

| File | Change |
|---|---|
| `lib/apothecary.ex` | Add `platform_mode?/0` helper |
| `lib/apothecary/application.ex` | Conditionally add platform GenServers to supervision tree |
| `lib/apothecary/bootstrapper.ex` | Guard: create DB + inject env config only in platform mode |
| `lib/apothecary/project.ex` | Add `domain_slug`, `secret_key_base`, `production_port` fields |
| `lib/apothecary/store.ex` | Migrate projects table for new fields |
| `lib/apothecary/pr_monitor.ex` | Guard: trigger `ProductionServer.rebuild` on PR merge |
| `lib/apothecary/dev_server.ex` | Guard: call `CaddyManager` on preview start/stop, create branch DB |
| `lib/apothecary/dev_config.ex` | Guard: inject `DATABASE_URL`, `SECRET_KEY_BASE` into auto-detected env |
| `lib/apothecary/brewer.ex` | Add local-merge mode in `finalize_worktree` |
| `lib/apothecary/worktree_manager.ex` | Guard: call `ProjectDatabase.drop_branch_database` on worktree deletion |
| `config/runtime.exs` | Add `PLATFORM_DOMAIN` → sets `:platform_mode` + `:platform_domain` |
| Dashboard LiveView | Conditionally render production controls, domain display, deploy status |

## New Files

| File | Purpose |
|---|---|
| `lib/apothecary/production_server.ex` | Production runtime manager (GenServer) |
| `lib/apothecary/caddy_manager.ex` | Caddy reverse proxy API client (GenServer) |
| `lib/apothecary/project_database.ex` | Postgres DB lifecycle for user projects (create/drop/migrate) |
| `lib/apothecary/project_env.ex` | Per-project environment variable generation |
| `Caddyfile` | Base Caddy config with admin API enabled |
| `setup.sh` | One-line VM setup script |

---

## Phased Implementation

### Phase 1 — MVP: Projects Run on Domains
1. `platform_mode?/0` helper + conditional supervision tree
2. `ProjectDatabase` module — create/drop Postgres databases for user projects, run migrations
3. Extend `Bootstrapper` — auto-generate `preview.yml`, create prod DB (guarded)
4. `ProductionServer` — Erlang Port running `MIX_ENV=prod mix phx.server`
5. `CaddyManager` — dynamic subdomain routing via Caddy admin API
6. Wire auto-deploy: PRMonitor merge → `ProductionServer.rebuild` (guarded)
7. Extend `Project` struct + Store migration for new fields
8. `ProjectEnv` — environment variable generation
9. Dashboard: conditionally show production URL, server status, start/stop controls
10. `setup.sh` — one-line VM provisioning script
11. Caddyfile base config

### Phase 2 — Polish
12. Local auto-merge mode in Brewer (per-project setting)
13. Branch database isolation (per-branch DBs for previews, cleaned up with worktrees)
14. Compiled releases for production (zero-downtime swap)
15. Deploy history in dashboard (timestamps, commit SHAs)

### Phase 3 — Platform Hardening
16. Resource limits (memory/CPU per project process, cgroups)
17. Custom domains per project (Caddy ACME HTTP challenge)
18. Project templates (vanilla, with auth, with admin)
19. Monitoring dashboard (health checks for all production services)

---

## Verification (Phase 1)

### Platform mode
1. Run `setup.sh myapp.example.com` on fresh VM → everything installs and starts
2. Create project via dashboard → Postgres DB created, `.apothecary/preview.yml` generated
3. Start production → `{slug}.myapp.example.com` serves the Phoenix app
4. Create worktree, start preview → `{branch}--{slug}.myapp.example.com` works, branch DB created
5. Merge PR → production auto-rebuilds with new code
6. Delete worktree → branch database cleaned up automatically
7. Restart Apothecary → production servers auto-recover from Mnesia state
8. LiveView WebSocket works through Caddy proxy (critical!)

### Local mode (regression check)
9. Start Apothecary WITHOUT `PLATFORM_DOMAIN` → no platform GenServers start
10. Create project, create worktree, run agents → everything works as before
11. No Caddy/Postgres dependency, no errors from missing platform services
12. Dashboard shows no deploy controls
