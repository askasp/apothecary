# Apothecary

A BEAM-orchestrated swarm manager for [Claude Code](https://docs.anthropic.com/en/docs/claude-code) agents. Apothecary uses [Beads](https://github.com/beads-project/beads) (`bd`) for dependency-aware task tracking and git worktrees for agent isolation, all coordinated through a real-time Phoenix LiveView dashboard.

## How It Works

Apothecary manages a pool of autonomous Claude Code agents that pull work from a shared task queue:

1. **Poller** periodically queries `bd` for ready (unblocked) tasks
2. **Dispatcher** claims ready tasks and assigns them to idle agents
3. **AgentWorker** checks out a git worktree, spawns `claude -p` as an OS process, and streams NDJSON output
4. On completion the worker closes the bead, releases the worktree, and signals the dispatcher for more work

No database is involved. All state comes from polling the `bd` CLI and managing OS processes. The LiveView dashboard subscribes via PubSub for real-time updates.

## Architecture

```
Apothecary.Supervisor (one_for_one)
+-- Phoenix.PubSub
+-- Apothecary.Poller          polls bd list/ready/stats every 2s
+-- Apothecary.WorktreeManager manages <project>-worktrees/
+-- Apothecary.AgentSupervisor DynamicSupervisor for N workers
+-- Apothecary.Dispatcher      claims tasks, assigns to idle agents
+-- ApothecaryWeb.Endpoint     LiveView dashboard
```

### Key Modules

| Module | Purpose |
|--------|---------|
| `Apothecary.Poller` | Polls `bd list/ready/stats --json`, broadcasts via PubSub |
| `Apothecary.Dispatcher` | Task assignment orchestration, swarm start/pause |
| `Apothecary.AgentWorker` | Port-based Claude Code process with NDJSON streaming |
| `Apothecary.AgentSupervisor` | DynamicSupervisor managing the agent pool |
| `Apothecary.WorktreeManager` | Git worktree lifecycle (create/recycle/release) |
| `Apothecary.Beads` | `bd` CLI wrapper (list, ready, claim, close, create, stats) |
| `Apothecary.CLI` | Low-level shell command execution via `Port.open` |
| `Apothecary.Git` | Git operations (worktrees, branches, pull) |
| `Apothecary.Startup` | Boot-time validation (project dir, git, bd, claude) |
| `ApothecaryWeb.DashboardLive` | Main dashboard: stats, tasks, agents, swarm controls |
| `ApothecaryWeb.TaskDetailLive` | Task detail with dependencies and claim/close actions |
| `ApothecaryWeb.AgentLive` | Agent detail with real-time output streaming |

## Prerequisites

- **Elixir** >= 1.15 and **Erlang/OTP**
- **Node.js** (for asset tooling)
- **[bd (Beads CLI)](https://github.com/beads-project/beads)** >= 0.56 &mdash; task tracking
- **[Claude Code CLI](https://docs.anthropic.com/en/docs/claude-code)** &mdash; agent execution
- **Git** &mdash; worktree management
- A git repository to manage (the "project directory")

## Quick Start

```bash
# Clone and install dependencies
git clone <repo-url> && cd apothecary
mix setup

# Point at the project you want agents to work on
export APOTHECARY_PROJECT_DIR=/path/to/your/project

# Start the server
mix phx.server
```

Visit [localhost:4000](http://localhost:4000) to open the dashboard.

## Configuration

All configuration is via environment variables, with sensible defaults:

| Variable | Default | Description |
|----------|---------|-------------|
| `APOTHECARY_PROJECT_DIR` | Current working directory | Path to the git repo agents will work in |
| `APOTHECARY_POLL_INTERVAL` | `2000` | Milliseconds between `bd` polls |
| `APOTHECARY_BD_PATH` | `bd` | Path to the Beads CLI binary |
| `APOTHECARY_CLAUDE_PATH` | `claude` | Path to the Claude Code CLI binary |
| `PORT` | `4000` | HTTP port for the web server |
| `SECRET_KEY_BASE` | (dev has default) | Required in production &mdash; generate with `mix phx.gen.secret` |
| `PHX_HOST` | `example.com` | Hostname for production URL generation |

## Development

```bash
# Install dependencies
mix deps.get

# Set up assets (esbuild + tailwind)
mix assets.setup

# Start dev server with live reload
mix phx.server

# Or start inside IEx
iex -S mix phx.server

# Run tests
mix test

# Run the full precommit suite (compile warnings-as-errors, format, test)
mix precommit
```

### Tech Stack

- **Phoenix 1.8** with **LiveView 1.1** for real-time UI
- **Tailwind CSS v4** + **daisyUI** for styling
- **Bandit** HTTP server
- **Beads** (Dolt-backed) for task tracking with dependency graphs
- **Claude Code CLI** in headless `-p` mode for agent execution

## Dashboard

The dashboard at `/` provides:

- **Stats bar** &mdash; task counts by status, agent utilization
- **Task list** &mdash; all beads with priority, type, status, and blockers
- **Agent cards** &mdash; live status, current task, branch, and output preview
- **Swarm controls** &mdash; start/pause the dispatcher, scale the agent pool
- **Create task form** &mdash; create new beads directly from the UI

Individual pages:

- `/tasks/:id` &mdash; task detail with full description, dependency tree, and claim/close actions
- `/agents/:id` &mdash; agent detail with scrolling real-time output stream

## How Agents Work

Each agent follows this lifecycle:

1. Dispatcher finds an idle worker and a ready (unblocked) bead
2. Worker claims the bead via `bd update <id> --claim`
3. WorktreeManager provides a clean git worktree on a feature branch
4. Worker spawns `claude -p "<prompt>" --dangerously-skip-permissions --output-format stream-json`
5. NDJSON output is parsed and broadcast to the dashboard in real time
6. On exit: worker closes the bead, releases the worktree, notifies the dispatcher

Agents receive a prompt that includes:
- The task title and description
- The project's `CLAUDE.md` and `AGENTS.md` guidelines
- Instructions to commit, push, and create a PR on their feature branch

## License

Private. All rights reserved.
