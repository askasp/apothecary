# Mnesia vs Beads/Dolt: Architecture Decision

## Background

Apothecary is a BEAM-orchestrated swarm manager that coordinates Claude Code agents
working in parallel across git worktrees. It needs to track two kinds of state:

1. **Work items** — worktrees (units of work/PRs) and tasks (steps within a worktree)
2. **Code changes** — the actual files agents produce, managed via git

The original system used **Beads** (backed by **Dolt**) for work item tracking.
The current system uses **Mnesia** — Erlang/OTP's built-in distributed database.

This document explains why the switch was made and clarifies what lives in the
database versus what lives in git.

---

## The Beads/Dolt Approach (Original)

### How It Worked

Beads is a CLI tool (`bd`) backed by Dolt, a SQL database with git-like versioning.
Apothecary interacted with it entirely through shell commands:

```
bd list --json          → list all tasks
bd ready --json         → list unblocked tasks
bd create "title"       → create a task
bd close <id> --reason  → mark task done
bd update <id> --notes  → add progress notes
bd dep add <a> <b>      → wire dependencies
```

Every operation shelled out via `Port.open` through the `CLI` module, parsed the
JSON response, and converted it into an `Apothecary.Bead` struct.

### The Poller Pattern

Since Beads had no way to push notifications, Apothecary ran a **Poller** GenServer
that called `bd list`, `bd ready`, and `bd stats` every 2 seconds, then broadcast
the results over PubSub for the LiveView dashboard.

### Problems

| Issue | Impact |
|-------|--------|
| **Shell overhead** | Every read/write spawned an OS process, parsed JSON, added ~50-200ms latency per call |
| **Polling, not reactive** | 2-second polling meant stale state and wasted CPU cycles |
| **External dependency** | Required `bd` binary installed, Dolt server running, correct `$PATH` |
| **No atomic operations** | Race conditions on concurrent claims — two agents could claim the same task |
| **Agent coupling** | Agents needed `bd` in their worktree environment and ran CLI commands directly |
| **Schema mismatch** | Dolt's schema (40+ fields including `wisp_type`, `mol_type`, `rig`, `hook_bead`) was designed for a general-purpose issue tracker, not Apothecary's specific domain |
| **`.beads/` in git** | Config and backup files lived in the repo — task state bled into code history |

---

## The Mnesia Approach (Current)

### How It Works

Mnesia is Erlang/OTP's built-in distributed database. It runs inside the same BEAM
VM as Apothecary — no external processes, no serialization boundaries, no network hops.

**Two Mnesia tables:**

```
:apothecary_worktrees
  [:id, :status, :title, :priority, :git_path, :git_branch,
   :parent_worktree_id, :assigned_agent_id, :data]

:apothecary_tasks
  [:id, :worktree_id, :status, :title, :priority, :data]
```

The `:data` field is an Elixir map holding flexible fields (description, notes,
timestamps, blockers, dependents) — no 40-column schema, just what Apothecary needs.

### Key Advantages

| Advantage | Detail |
|-----------|--------|
| **Zero latency** | Reads are in-process ETS lookups (~microseconds). Writes are Mnesia transactions (~milliseconds) |
| **Atomic claims** | `claim_worktree/2` uses `wread` (write-lock read) inside a transaction — no race conditions |
| **Reactive** | Every mutation calls `schedule_broadcast()` which debounces a PubSub push (50ms). No polling needed |
| **No external deps** | Mnesia ships with OTP. No binary to install, no server to manage |
| **Agent communication via MCP** | Agents use MCP tools (HTTP) instead of shelling out to `bd`. No CLI needed in worktrees |
| **Domain-specific schema** | Only the fields Apothecary needs. Two-level model (worktree → tasks) is first-class |
| **Persistence options** | `disc_copies` in dev (survives restarts), `ram_copies` in test (fast, disposable) |

### The TaskManager

`TaskManager` is a single GenServer that replaces both the `Poller` and `Beads`
modules. It provides:

- **CRUD** for worktrees and tasks via Mnesia transactions
- **Ready computation** — which worktrees are unblocked and unassigned
- **Dependency management** — cycle detection, automatic unblocking when blockers complete
- **Dashboard API** — `get_state/0` returns the same shape the Poller used to produce
- **PubSub broadcast** — debounced (50ms) so rapid mutations don't flood subscribers

### MCP Instead of CLI

Agents no longer shell out to `bd`. Instead, the orchestrator runs an MCP server
(via Hermes) at `/mcp`, and agents connect with scoping parameters:

```
?agent_id=1&worktree_id=wt-abc123
```

Seven MCP tools replace the `bd` CLI commands:

| MCP Tool | Replaces |
|----------|----------|
| `list_tasks` | `bd list --json` |
| `get_task` | `bd show <id> --json` |
| `create_task` | `bd create "title"` |
| `complete_task` | `bd close <id>` |
| `add_notes` | `bd update <id> --notes` |
| `add_dependency` | `bd dep add <a> <b>` |
| `worktree_status` | `bd ready --json` + `bd stats --json` |

The MCP approach means agents don't need any special tooling installed in their
worktree — they communicate over HTTP, scoped to their assigned worktree.

---

## What Is in Git vs What Is Not

This is the critical distinction. Git manages **code**. Mnesia manages **work state**.

### In Git (Versioned, Committed, Pushed)

| What | Where | Purpose |
|------|-------|---------|
| Application source code | `lib/`, `test/`, `config/` | The actual Elixir/Phoenix application |
| Agent code changes | Feature branches in worktrees | Work product — what agents create |
| Static config | `config/*.exs`, `mix.exs` | Application configuration (compile-time) |
| Documentation | `docs/`, `README.md`, `AGENTS.md` | Project docs, agent instructions |
| Assets | `assets/` | JS, CSS, static files |

### NOT in Git (Runtime State, Ephemeral)

| What | Where | Purpose |
|------|-------|---------|
| Worktree records | Mnesia `:apothecary_worktrees` table | Tracks each unit of work: status, assignment, git path, priority |
| Task records | Mnesia `:apothecary_tasks` table | Tracks steps within worktrees: status, notes, dependencies |
| Agent state | In-memory (AgentWorker GenServer) | Output buffer, execution status, PID |
| Dispatcher state | In-memory (Dispatcher GenServer) | Agent pool, idle/working counts |
| Mnesia data files | `Mnesia.<node>@<host>/` directory | Mnesia's on-disk persistence (if using disc_copies) |
| `.mcp.json` | Written to worktree dir at agent spawn | Tells Claude where the MCP server is — ephemeral, not committed |

### The Old Way (Beads/Dolt) Blurred This Line

With Beads, task state lived in `.beads/` inside the git repository:

```
.beads/
├── config.yaml          ← committed to git
├── backup/
│   ├── issues.jsonl     ← committed to git (task state in version history!)
│   └── events.jsonl     ← committed to git (audit trail in version history!)
├── dolt/                ← gitignored (Dolt's internal database)
├── bd.sock              ← gitignored (runtime socket)
└── ...
```

This meant `git log` was littered with `bd: backup` commits — automated Dolt sync
snapshots that had nothing to do with code changes. Task state changes (claiming,
closing, adding notes) produced git commits alongside actual code work.

### The New Way Keeps Them Separate

```
Git repo (versioned)          Mnesia (runtime state)
┌─────────────────┐          ┌──────────────────────┐
│ lib/             │          │ :apothecary_worktrees│
│ test/            │          │   wt-abc123 (open)   │
│ config/          │          │   wt-def456 (done)   │
│ assets/          │          │                      │
│ docs/            │          │ :apothecary_tasks    │
│ mix.exs          │          │   t-111 (open)       │
│                  │          │   t-222 (blocked)    │
│ (clean history   │          │   t-333 (done)       │
│  = code changes  │          │                      │
│  only)           │          │ (survives restarts   │
│                  │          │  via disc_copies)    │
└─────────────────┘          └──────────────────────┘
         │                              │
         ▼                              ▼
  Pushed to remote             Lives on the BEAM node
  PRs, reviews, merges         Queries are in-process
```

---

## Summary

| | Beads/Dolt | Mnesia |
|---|---|---|
| **Runtime** | External OS process (`bd` CLI + Dolt server) | In-process (same BEAM VM) |
| **Latency** | 50-200ms per operation (spawn, exec, parse JSON) | Microseconds (ETS read) to milliseconds (transaction) |
| **Concurrency** | No atomicity — race conditions on claims | Mnesia transactions with write locks |
| **State updates** | Polling every 2 seconds | Reactive PubSub broadcast (50ms debounce) |
| **Agent interface** | `bd` CLI commands in shell | MCP tools over HTTP |
| **Schema** | 40+ fields (general-purpose issue tracker) | 6-10 fields (domain-specific) |
| **Dependencies** | `bd` binary, Dolt, correct PATH | None (OTP built-in) |
| **Git pollution** | `bd: backup` commits, `.beads/` in repo | Clean git history — only code commits |
| **Persistence** | Dolt database + JSONL backups in `.beads/` | `disc_copies` (dev) or `ram_copies` (test) |
| **Distribution** | Single-node only | Mnesia supports multi-node (future clustering) |

The migration from Beads/Dolt to Mnesia aligns Apothecary's data layer with its
runtime: everything runs on the BEAM, everything communicates through BEAM-native
mechanisms (GenServer calls, Mnesia transactions, PubSub broadcasts), and git history
stays clean — containing only the code that agents actually write.
