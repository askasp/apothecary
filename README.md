# Apothecary

I tried running an entire [Gas Town](https://github.com/nomadkaraoke/gastown). Turns out that's a lot. But an apothecary? That I can manage.

Apothecary is a small Elixir app that runs multiple Claude Code agents in parallel. You give it work, it spins up agents in isolated git worktrees, they do the coding, and PRs come out the other end. It's inspired by [Beads](https://github.com/steveyegge/beads) and Gas Town, but uses the BEAM for process supervision - so when an agent crashes, it just gets restarted.

## How it works

1. You create a **concoction** - each one gets its own git worktree, completely isolated from the others
2. An idle **alchemist** picks it up automatically
3. Claude Code spawns in the worktree, reads the task, and starts coding
4. If the work is complex, the alchemist breaks it into **ingredients** (sub-tasks) on its own
5. When it's done, the branch gets pushed and a PR opens
6. If reviewers request changes, an alchemist gets re-dispatched to address them

The whole thing is reactive via PubSub - no polling. State changes propagate and idle alchemists pick up work immediately.

## The naming

| Term | What it is |
|------|-----------|
| **Concoction** | A feature in its own isolated worktree - one concoction, one branch, one PR (`wt-*` IDs) |
| **Ingredient** | A step within a concoction (`t-*` IDs) |
| **Alchemist** | A Claude Code agent process that works on concoctions |
| **Recipe** | A template for creating concoctions from issues |

## Why Elixir

Each alchemist is a GenServer under a DynamicSupervisor. Agent crashes are isolated - one going down doesn't affect the others. Mnesia handles all the state so there's no external database to set up. Phoenix PubSub makes the dispatch reactive, and LiveView gives you a real-time dashboard without writing JavaScript.

The BEAM is good at running lots of concurrent processes that talk to each other and occasionally fall over. That's exactly what this is.

## Tech stack

- **Phoenix 1.8** + **LiveView 1.1** - web framework and real-time dashboard
- **Mnesia** - Erlang's built-in database (no Postgres, no Redis)
- **Hermes MCP** - agent-to-orchestrator communication
- **Claude Code CLI** - headless mode for autonomous coding
- **Tailwind v4** + **daisyUI** - dashboard styling

## Getting started

```bash
mix setup
mix phx.server
```

Visit [`localhost:4000`](http://localhost:4000). You'll need Claude Code CLI on your PATH.

## License

MIT
