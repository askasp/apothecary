# Apothecary - A Parallel AI Agent Swarm That Ships PRs

For those of us who tried running an entire [Gas Town](https://github.com/nomadkaraoke/gastown), it got out of hand pretty quickly. But I can manage an apothecary.

Apothecary is heavily inspired by [Beads](https://github.com/steveyegge/beads) and [Gas Town](https://github.com/nomadkaraoke/gastown), but swaps out the orchestration layer for **Elixir and the BEAM VM** - getting fault tolerance, process supervision, and automatic agent restarts for free. When an agent crashes at 3am, Apothecary picks it back up and keeps going.

## What It Does

You give it work. It spins up Claude Code agents in isolated git worktrees, lets them cook in parallel, and opens PRs when they're done. That's it.

- **Parallel worktree isolation** - Each unit of work gets its own git worktree branch. Agents work simultaneously without stepping on each other.
- **Auto-decomposition** - Agents break down complex tasks into ingredients (sub-tasks) on their own. No need to hand-hold the planning.
- **Automatic PR creation** - When an agent finishes, Apothecary pushes the branch and opens a GitHub PR. If reviewers request changes, it re-dispatches an agent to address them.
- **Agent state survival** - Progress notes and git history persist across crashes. When an agent goes down, the next one picks up where it left off with full context.
- **Agent takeover** - If a brewer (agent process) dies or gets stuck, a fresh one can take over the same concoction and keep working.
- **Live dashboard** - Real-time Phoenix LiveView UI showing all agents, their work, streaming output, and PR status.
- **Scaling on the fly** - Add or remove agents at runtime from the dashboard.

## Demo

<!-- TODO: Add demo video/gif here -->
*Demo video coming soon*

## How It Works

```
You create a Concoction (unit of work)
        |
        v
  Dispatcher assigns it to an idle Brewer
        |
        v
  WorktreeManager creates an isolated git branch
        |
        v
  Brewer spawns a Claude Code process via MCP
        |
        v
  Claude reads the task, decomposes into Ingredients if needed
        |
        v
  Claude implements, commits, marks ingredients done
        |
        v
  Brewer pushes branch, opens PR via GitHub CLI
        |
        v
  PR Monitor watches for merge/review feedback
```

The whole thing is reactive - the Dispatcher subscribes to state changes via PubSub, so there's no polling. When an ingredient gets completed, the system immediately knows and can dispatch the next piece of work.

## The Naming

The apothecary metaphor runs deep:

| Concept | What it actually is |
|---------|-------------------|
| **Concoction** | A unit of work that becomes a PR. Lives in its own git worktree (`wt-*` IDs). |
| **Ingredient** | A task/step within a concoction (`t-*` IDs). Created by agents to decompose complex work. |
| **Brewer** | A Claude Code agent process. Spawned by the supervisor, talks to the orchestrator via MCP, does the actual coding. |
| **Recipe** | A template for creating concoctions from issues or descriptions. |

## Why Elixir?

This is the exact kind of problem the BEAM was built for:

- **Supervision trees** - Each brewer is a GenServer under a DynamicSupervisor. Agent crashes are isolated and automatically handled. No agent can take down the system.
- **Lightweight processes** - Spinning up 10 concurrent agents is trivial. Each one is just an Erlang process with a Port to Claude.
- **Mnesia** - All state lives in Mnesia (Erlang's built-in distributed database). No Postgres, no Redis, no external dependencies. It just works.
- **PubSub** - Phoenix PubSub gives us reactive, event-driven dispatch. State changes propagate instantly across the system without polling.
- **Fault tolerance** - A 5-minute watchdog detects stuck agents. Exponential backoff prevents rapid failure loops. The whole system is designed to self-heal.
- **LiveView** - Real-time dashboard with zero JavaScript frameworks. Server-rendered, WebSocket-powered, streaming agent output live.

## Tech Stack

- **Phoenix 1.8** + **LiveView 1.1** - Web framework and real-time UI
- **Mnesia** - Built-in Erlang database for all state (no external DB)
- **Hermes MCP** - Model Context Protocol for agent-to-orchestrator communication
- **Claude Code CLI** - Headless mode (`-p` flag) for autonomous coding
- **Tailwind v4** + **daisyUI** - Dashboard styling
- **Burrito** - Cross-platform binary releases (Linux, macOS)

## Getting Started

```bash
# Install dependencies
mix setup

# Start the server
mix phx.server
```

Then visit [`localhost:4000`](http://localhost:4000) to see the dashboard.

You'll need Claude Code CLI installed and available on your PATH.

## License

MIT
