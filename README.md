# Apothecary

A BEAM-orchestrated swarm manager for [Claude Code](https://docs.anthropic.com/en/docs/claude-code) agents. Apothecary uses [Beads](https://github.com/knute-legal/beads) (`bd`) for task tracking and git worktrees for agent isolation, coordinated through a real-time Phoenix LiveView dashboard.

## How It Works

Apothecary runs a pool of Claude Code agents as supervised OS processes. Each agent gets its own git worktree so agents can work on separate tasks in parallel without conflicts. A poller watches the beads task queue for ready work, and a dispatcher assigns unblocked tasks to idle agents.

```
                    ┌─────────────────┐
                    │  LiveView UI    │
                    │  (Dashboard)    │
                    └────────┬────────┘
                             │ PubSub
              ┌──────────────┼──────────────┐
              │              │              │
       ┌──────┴──────┐ ┌────┴────┐ ┌───────┴───────┐
       │   Poller    │ │Dispatch │ │   Worktree    │
       │ (bd poll)   │ │  er     │ │   Manager     │
       └──────┬──────┘ └────┬────┘ └───────┬───────┘
              │              │              │
              │        ┌─────┴─────┐        │
              │        │  Agent    │        │
              │        │Supervisor │        │
              │        └─────┬─────┘        │
              │         ┌────┼────┐         │
              │         │    │    │         │
              │        ┌┴┐  ┌┴┐  ┌┴┐       │
              │        │W│  │W│  │W│       │
              │        │1│  │2│  │3│       │
              │        └─┘  └─┘  └─┘       │
              │       AgentWorkers          │
              │      (Claude Code           │
              │       via Port)             │
              └─────────────────────────────┘
                     bd CLI / git
```

**No database required** -- all state comes from polling the `bd` CLI and in-memory GenServer state.

## Architecture

| Module | Role |
|---|---|
| `Apothecary.Poller` | Polls `bd list/ready/stats --json` every 2s, broadcasts via PubSub |
| `Apothecary.Dispatcher` | Claims ready tasks and assigns them to idle agents |
| `Apothecary.AgentWorker` | Spawns `claude -p "..." --output-format stream-json` as a Port, streams NDJSON output |
| `Apothecary.AgentSupervisor` | DynamicSupervisor managing 1-10 worker processes |
| `Apothecary.WorktreeManager` | Creates and recycles git worktrees under `<project>-worktrees/` |
| `Apothecary.Beads` | Wrapper around the `bd` CLI for task CRUD |

## Prerequisites

- **Elixir** >= 1.15
- **Beads** (`bd`) >= v0.56 -- [install instructions](https://github.com/knute-legal/beads)
- **Claude Code** (`claude`) -- [install instructions](https://docs.anthropic.com/en/docs/claude-code)
- **Git** -- for worktree management
- A git repository with beads initialized (`bd init`)

## Getting Started

```bash
# Install dependencies and build assets
mix setup

# Start the server
mix phx.server
```

Visit [localhost:4000](http://localhost:4000) to open the dashboard.

From the dashboard you can:

1. View all tasks from the beads queue
2. Create new tasks
3. Start a swarm of 1-10 Claude Code agents
4. Watch agents claim and work on tasks in real time
5. Inspect individual agent output streams

## Configuration

Environment variables (set in shell or `.env`):

| Variable | Default | Description |
|---|---|---|
| `APOTHECARY_PROJECT_DIR` | current directory | Path to the git project beads manages |
| `APOTHECARY_POLL_INTERVAL` | `2000` | Milliseconds between `bd` polls |
| `APOTHECARY_BD_PATH` | `bd` | Path to the `bd` binary |
| `APOTHECARY_CLAUDE_PATH` | `claude` | Path to the `claude` binary |
| `PORT` | `4000` | HTTP server port |

Production additionally requires `SECRET_KEY_BASE` and `PHX_HOST`.

## Routes

| Path | View | Description |
|---|---|---|
| `/` | `DashboardLive` | Main swarm dashboard with task board and agent controls |
| `/tasks/:id` | `TaskDetailLive` | Task details, dependency tree, claim/close actions |
| `/agents/:id` | `AgentLive` | Agent status and live output stream |

## Development

```bash
# Run the precommit quality gate (compile, format, test)
mix precommit

# Run tests
mix test

# Run a specific test file
mix test test/path/to/test.exs
```

## Agent Lifecycle

1. **Idle** -- Agent is registered with the Dispatcher, waiting for work
2. **Starting** -- Dispatcher assigns a task; agent checks out a worktree
3. **Working** -- `claude -p "<prompt>" --dangerously-skip-permissions --output-format stream-json` runs as a Port
4. **Completing** -- On exit, agent closes the bead (success) or logs failure, releases the worktree
5. **Idle** -- Agent signals the Dispatcher it's ready for the next task

Each agent operates in its own git worktree branch (`agent-<id>-<timestamp>`), so multiple agents can modify the same codebase concurrently without conflicts.

## Tech Stack

- [Phoenix](https://www.phoenixframework.org/) 1.8 + [LiveView](https://hexdocs.pm/phoenix_live_view) 1.1
- [Tailwind CSS](https://tailwindcss.com/) v4 + [daisyUI](https://daisyui.com/)
- [Beads](https://github.com/knute-legal/beads) (Dolt-backed task tracking)
- [Claude Code](https://docs.anthropic.com/en/docs/claude-code) CLI in headless mode
