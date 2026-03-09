# Apothecary - Neovim for AI Agents

I tried running an entire [Gas Town](https://github.com/steveyegge/gastown). Turns out that's a lot. But an apothecary? That I can manage.

Apothecary is a small Elixir app that runs multiple Claude Code agents in parallel. You give it work, it spins up agents in isolated git worktrees, they do the coding, and PRs come out the other end. It's inspired by [Beads](https://github.com/steveyegge/beads) and Gas Town, but uses the BEAM for process supervision — so when an agent crashes, it just gets restarted. Agents continuously write notes on what they discover that are recovered on a crash restart.


## DEMO

https://github.com/askasp/apothecary/releases/download/v0.1.12/ApotheacryIntro.mp4

## How it works

1. You create a **worktree** — it gets its own git worktree branch, completely isolated
2. An idle agent picks it up automatically
3. Claude Code spawns in the worktree, reads the task, and starts coding
4. If the work is complex, the agent breaks it into **tasks** (sub-steps) on its own
5. When done, the branch gets pushed and a PR opens
6. If reviewers request changes, an agent gets re-dispatched to address them

The whole thing is reactive — no polling. State changes propagate instantly and idle agents pick up work as soon as it appears.

## Getting started

### Prerequisites

- [Claude Code CLI](https://docs.anthropic.com/en/docs/claude-code) on your PATH
- A GitHub repo you want agents to work on
- (Optional) [GitHub CLI](https://cli.github.com/) (`gh`) for automatic PR creation and merging — without it, Apothecary runs in local merge mode

### Install

```bash
curl -fsSL https://raw.githubusercontent.com/askasp/apothecary/main/install.sh | bash
```

Or download a binary directly from [GitHub Releases](https://github.com/askasp/apothecary/releases/latest).

### Run

`cd` into the repo you want agents to work on and start apothecary:

```bash
cd /path/to/your/repo
apothecary
```

Visit [`localhost:4000`](http://localhost:4000) to open the dashboard. Create a worktree, and an agent will pick it up.

### Configuration

Apothecary works out of the box with zero config, but you can tweak things with environment variables:

| Variable | Default | What it does |
|----------|---------|-------------|
| `PORT` | `4000` | Dashboard port |
| `APOTHECARY_PROJECT_DIR` | current directory | Git repo to work on |
| `APOTHECARY_MERGE_MODE` | auto-detected | `github` or `local` |
| `APOTHECARY_CLAUDE_PATH` | `claude` | Path to Claude Code CLI |

### From source

If you'd rather run from source (requires Elixir):

```bash
git clone https://github.com/askasp/apothecary.git
cd apothecary
mix setup
mix phx.server
```

### Preview setup

To enable dev server previews for your project, add `.apothecary/preview.yml` to your repo:

```yaml
command: "npm run dev"        # Required — the command to start the dev server
setup: "npm install"          # Optional — runs once before the first start
shutdown: "pkill -f vite"     # Optional — custom shutdown command (default: SIGTERM)
base_port: 5173               # Optional — auto-detected from command if omitted
port_count: 2                 # Required (unless ports list provided)
ports:                        # Optional — names and offsets for allocated ports
  - name: web
    offset: 0
  - name: vite-hmr
    offset: 1
env:                          # Optional — extra environment variables
  NODE_ENV: development
```

Apothecary injects a `BASE_PORT` env variable so your dev server knows which port to bind to. Ports are allocated automatically so multiple worktree previews can run side by side without conflicts.

**Auto-detection:** If no `preview.yml` exists, Apothecary tries to detect your stack automatically — Phoenix projects get `mix phx.server`, Node projects get `npm run dev` (or `bun` if a lockfile is present). Add a `preview.yml` when you need custom ports, setup commands, or environment variables.

## What you can do with it

### Run a swarm overnight, wake up to PRs

Create a batch of worktrees before bed — refactors, bug fixes, feature stubs, whatever. The agents work through the queue in parallel while you sleep. In the morning you've got a stack of PRs to review instead of a pile of tickets to start.

### Scale to as many agents as you can handle

Set the agent count with `+`/`-`. Scale to as many parallel agents as your machine (and Claude Code subscription) can handle. You can change the count while agents are already working — new ones spin up, extras wind down gracefully.

### Talk to agents while they work

Select a worktree that's being brewed and type into the input bar — it goes straight to the agent's stdin.

### Preview what agents built before merging

Drop a `.apothecary/preview.yml` in your repo and any worktree can spin up a live dev server right in its worktree. Apothecary allocates ports so multiple previews don't conflict. You get an inline preview right in the dashboard — see what the agent built without leaving the browser.

### Review diffs without leaving the dashboard

Press `d` on any worktree and get a full-screen diff viewer — file list on the left, syntax-colored diff on the right. Files are color-coded: green for additions, yellow for mixed changes, red for deletions. Navigate with `j`/`k`, close with `Esc`.

### Set up recurring work with recipes

Recipes are cron-scheduled templates that automatically create worktrees. Want dependency updates every Sunday at 3 AM? A weekly linting pass? Create a recipe with a cron expression, enable it, and it fires on schedule. The scheduler survives restarts and recalculates next-run times on startup. Set it and forget it.

### Automatic PR revision cycles

When a reviewer requests changes on a PR, Apothecary notices (it polls GitHub every 60 seconds), marks the worktree as needing revision, and dispatches an agent to go fix it. The agent reads the review comments and pushes new commits to the existing PR. You don't have to do anything — just leave your review and walk away.

## What keeps it running

Agents crash. They hang. They run out of memory. They hit rate limits. That's fine — the system handles all of it automatically.

**Automatic retries** — When an agent fails for any reason, the worktree goes back into the queue and an idle agent picks it up. No manual intervention. The agent that picks it up reads the previous agent's notes and continues where it left off. A single worktree can be retried as many times as needed until it succeeds.

**Watchdog** — Each agent has a 5-minute silence timer. If Claude stops producing output for that long, the watchdog kills the process, logs the last 30 lines of output, and releases the worktree back to the pool. This catches hangs, deadlocks, and runaway processes before they waste your Claude credits.

**Context survival** — Agents log progress notes as they work: what they tried, what worked, key decisions. These notes are stored in Mnesia and get included in the prompt when the next agent picks up the worktree. Crash diagnostics get written to notes automatically too. So retried agents don't start from scratch — they pick up with full context of what happened before.

**Supervision** — Every agent process runs under an OTP supervisor. If an agent's OS process dies unexpectedly, the supervisor detects it immediately and cleans up. There's no zombie state, no leaked resources, no worktrees stuck in limbo.

Between these layers, the system is self-healing. Stuck agents get recycled, crashed agents get retried, and context survives across restarts. You can queue up work and walk away — it sorts itself out.

## The dashboard

The dashboard is a Phoenix LiveView app — real-time updates, no page refreshes, and entirely keyboard-driven. The design is inspired by Neovim: modal, composable, and fast.

### Layout

The left panel shows worktrees grouped by status:

| Group | What's in it |
|-------|-------------|
| **Queued** (`1`) | Ready and waiting for an agent |
| **Brewing** (`2`) | Currently being worked on by an agent |
| **Reviewing** (`3`) | PR is open, under review |
| **Done** (`4`) | Merged |
| **Discarded** (`5`) | Closed without merging |

Select a worktree to see its tasks, progress, agent notes, and live output in the right detail panel. Inline previews show what the agent built without leaving the dashboard.

### Workflow

The input bar is context-sensitive — what happens when you type depends on the current mode:

1. **Worktree mode** (`b`) — Type a title to create a new worktree. The agent picks it up and starts coding.
2. **Task mode** (`a`) — With a worktree selected, type to add a task (sub-step) to it.
3. **Chat mode** (`c` or `/`) — If an agent is working on the selected worktree, your text goes directly to the agent's stdin.
4. **Default** — `n` focuses the input without switching modes.

Press `Esc` to cancel any mode and return to normal navigation.

### Keyboard shortcuts

Everything is keyboard-navigable. Press `?` in the dashboard for the full list.

**Navigation:**

| Key | What it does |
|-----|-------------|
| `j` / `k` | Next / prev worktree |
| `h` / `l` | Focus tree / detail panel |
| `g` / `G` | First / last worktree |
| `Enter` | Open worktree detail |
| `Esc` / `q` | Back / cancel mode |
| `1`–`5` | Jump to status group |
| `w` | Focus worktree tree |
| `e` | Switch to recipes tab |
| `Ctrl+H/L` | Switch panels (works in input) |
| `Ctrl+J/K` | Cycle sections: tree → detail → input |
| `Cmd+K` | Project switcher |

**Actions:**

| Key | What it does |
|-----|-------------|
| `b` | New worktree |
| `a` | Add task to selected worktree |
| `c` / `/` | Chat with agent |
| `n` | Focus input |
| `s` | Start / stop brewing |
| `+` / `-` | Increase / decrease agent count |
| `J` / `K` | Reorder worktree priority |
| `d` | View diff |
| `D` | Toggle dev server preview |
| `p` | Open inline preview |
| `t` | Open terminal in worktree |
| `P` | Pull origin main |
| `R` | Requeue orphaned tasks |
| `m` | Merge PR |
| `r` | Requeue task |
| `x` | Close worktree |
| `?` | Show all shortcuts |

## The naming

| Term | What it is |
|------|-----------|
| **Worktree** | A unit of work — one git worktree, one branch, one PR (`wt-*` IDs) |
| **Task** | A step within a worktree (`t-*` IDs) |
| **Agent** | A Claude Code agent process |
| **Recipe** | A cron-scheduled template for recurring worktrees |

## Why Elixir

Erlang was built at Ericsson in the 1980s to manage millions of simultaneous phone calls. The requirements were: massive concurrency, processes that crash without taking down neighbors, hot code upgrades, and systems that self-heal without human intervention. They built the BEAM virtual machine for exactly this. Elixir runs on the same VM.

Managing a fleet of AI agents is essentially the same problem. You have N concurrent processes that need isolation, supervision, and automatic recovery. Each agent is a GenServer under a DynamicSupervisor — when one crashes, the supervisor handles it and the others keep working. There's no shared memory to corrupt, no thread pools to exhaust, no cascading failures. Mnesia (Erlang's built-in distributed database) handles all the state so there's no external database to set up. Phoenix PubSub makes the dispatch reactive, and LiveView gives you a real-time dashboard without writing any JavaScript.

The BEAM was designed for systems that run forever and recover from failure automatically. That's exactly what an agent orchestrator needs to do.

## WARNING

Brewing is not without risk. Agents are isolated into worktrees and sandboxed at the OS level — on macOS via `sandbox-exec` (seatbelt profiles restricting writes to the worktree), on Linux via `bwrap` (bubblewrap). But this is **NOT PRODUCTION-READY**. Agents can and will make mistakes. At the very least:

- **Protect your main branch** from force pushes
- **Require PRs for merging** (no direct pushes to main)
- **Require at least one code review** before merging

Do not point this at a repo you can't afford to have messy PRs on. You have been warned.

## Tech stack

- **Phoenix 1.8** + **LiveView 1.1** — web framework and real-time dashboard
- **Mnesia** — Erlang's built-in distributed database (no Postgres, no Redis, no nothing)
- **Hermes MCP** — agent-to-orchestrator communication
- **Claude Code CLI** — headless mode for autonomous coding
- **Tailwind v4** + **daisyUI** — dashboard styling

## License

MIT
