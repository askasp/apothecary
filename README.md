# Apothecary

A BEAM-orchestrated swarm manager for Claude Code agents. Apothecary coordinates multiple headless Claude Code instances working in parallel across isolated git worktrees, with a real-time Phoenix LiveView dashboard for monitoring and control.

## How It Works

Apothecary connects three systems together:

1. **Beads (`bd`)** — a dependency-aware task queue (the shared work backlog)
2. **Claude Code** — headless AI coding agents (the workers)
3. **Git worktrees** — isolated checkouts per agent (the workspaces)

The orchestration loop:

```
Beads task queue  ──>  Dispatcher  ──>  Agent Workers  ──>  Git worktrees
     (bd CLI)          (matches         (spawns Claude      (isolated
                        idle agents      as Port process)    branches)
                        to ready tasks)
```

### Architecture

```
Apothecary.Supervisor
├── Apothecary.Poller          — polls `bd` CLI every 2s, broadcasts state via PubSub
├── Apothecary.WorktreeManager — creates/recycles git worktrees for agents
├── Apothecary.AgentSupervisor — DynamicSupervisor managing N AgentWorker processes
├── Apothecary.Dispatcher      — matches idle agents to ready tasks, scales the swarm
└── ApothecaryWeb.Endpoint     — Phoenix server with LiveView dashboard
```

### Task Lifecycle

1. **Tasks are created** in beads (via dashboard UI or `bd create`)
2. **Poller** polls `bd list`, `bd ready`, and `bd stats` every 2 seconds and broadcasts updates
3. **Dispatcher** runs a dispatch loop every 3 seconds:
   - Queries beads for the next ready (unblocked) task
   - Claims it with `bd update <id> --claim`
   - Pops an idle agent from the queue and assigns the task
4. **AgentWorker** receives the task:
   - Checks out a fresh git worktree via `WorktreeManager`
   - Spawns `claude -p "<prompt>" --dangerously-skip-permissions --output-format stream-json` as an Erlang Port
   - Streams output via PubSub for live dashboard consumption
   - On exit(0): closes the bead, releases the worktree, returns to idle
   - On failure: logs notes to the bead, releases, returns to idle
5. **Dashboard** receives all updates via PubSub — no polling from the browser

### Agent Prompt

Each agent receives a structured prompt containing:
- The task details (ID, title, type, priority, description)
- Step-by-step instructions (read codebase, implement, test, commit, push)
- Rules (stay on feature branch, never push to main, include task ID in commits)
- Beads commands for self-decomposition of complex tasks
- Project guidelines from `CLAUDE.md` and `AGENTS.md`

Agents can create subtasks and wire dependencies using `bd` commands, enabling autonomous decomposition of complex work.

## Prerequisites

- **Elixir** ~> 1.15 and Erlang/OTP
- **Node.js** (for asset compilation)
- **Claude Code CLI** (`claude`) — [install instructions](https://docs.anthropic.com/en/docs/claude-code)
- **Beads CLI** (`bd`) — the task tracking backend

Ensure both `claude` and `bd` are available in your `PATH`. Apothecary validates these on startup and logs warnings if they're missing.

## Setup

```bash
# Install dependencies and build assets
mix setup

# Configure the project directory (the repo your agents will work on)
# Set in config/dev.exs or via runtime config:
#   config :apothecary, project_dir: "/path/to/your/project"

# Start the server
iex -S mix phx.server
```

Visit [localhost:4000](http://localhost:4000) to open the dashboard.

On first boot, Apothecary will:
- Validate the project directory is a git repo
- Initialize beads (`bd init`) if not already set up
- Write a default `CLAUDE.md` with agent instructions if one doesn't exist

## Usage

### Dashboard

The LiveView dashboard at `/` provides:

- **Stats bar** — total tasks, ready count, in-progress, completed, active agents
- **Task board** — filterable list of all tasks (all / ready / in progress / done / blocked)
- **Swarm controls** — slider to set agent count, start/stop buttons
- **Agent roster** — live status of each agent (idle, working, current task, last output)
- **Ready queue** — preview of unblocked tasks waiting for dispatch
- **Create task form** — add new tasks directly from the UI

Additional views:
- `/tasks/:id` — task detail page with dependency tree, claim/close actions
- `/agents/:id` — individual agent view with full streaming output

### Swarm Control

1. Set the desired number of agents using the slider (default: 3)
2. Click **Start Swarm** to spawn agent workers
3. Agents automatically pick up ready tasks and begin working
4. Scale up or down while running with **Set Agent Count**
5. Click **Stop Swarm** to terminate all agents

### CLI Task Management

You can also manage tasks directly with the `bd` CLI:

```bash
bd create "Implement feature X" -t feature -p 1 --json    # create a task
bd ready --json                                             # see unblocked tasks
bd update <id> --claim                                      # claim a task
bd close <id> --reason "Done"                               # close a completed task
bd dep add <blocked_id> <blocker_id>                        # wire dependencies
```

## Configuration

In `config/config.exs`:

```elixir
config :apothecary,
  project_dir: nil,          # path to the git repo agents will work on (required)
  poll_interval: 2_000,      # ms between beads polls
  bd_path: "bd",             # path to beads CLI
  claude_path: "claude"      # path to Claude Code CLI
```

## Development

```bash
# Run the precommit checks (compile warnings, format, test)
mix precommit

# Run tests
mix test

# Run a specific test file
mix test test/my_test.exs
```
