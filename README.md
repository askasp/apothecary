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

## What keeps it running

Agents crash. They hang. They run out of memory. Two things handle this:

**Watchdog** - Each alchemist has a 5-minute silence timer. If Claude stops producing output for that long, the watchdog kills the process, logs the last 30 lines of output and any in-progress ingredients, and releases the concoction back to the pool. An idle alchemist picks it up and tries again.

**Notes** - Alchemists log progress notes as they work (what they tried, what worked, key decisions). These notes are stored in Mnesia and get included in the prompt when the next alchemist picks up the concoction. So if an agent crashes halfway through, the replacement doesn't start from scratch - it reads what happened and continues from there. Crash diagnostics get written to notes automatically too.

Between the two, the system is self-healing. Stuck agents get recycled, and context survives across restarts.

## The naming

| Term | What it is |
|------|-----------|
| **Concoction** | A feature in its own isolated worktree - one concoction, one branch, one PR (`wt-*` IDs) |
| **Ingredient** | A step within a concoction (`t-*` IDs) |
| **Alchemist** | A Claude Code agent process that works on concoctions |
| **Recipe** | A template for creating concoctions from issues |

## What you can do with it

**Run a swarm overnight, wake up to PRs.** Create a batch of concoctions before bed - refactors, bug fixes, feature stubs, whatever. The agents work through the queue in parallel while you sleep. In the morning you've got a stack of PRs to review instead of a pile of tickets to start.

**Scale agents up or down on the fly.** The dashboard lets you set anywhere from 1 to 10 parallel agents. Running on a beefy machine? Crank it up. Want to keep things calm? Run one at a time. You can change the count while agents are already working - new ones spin up, extras wind down.

**Preview changes before merging.** Any concoction can spin up a dev server right in its worktree. Apothecary reads a `.apothecary/preview.yml` config, allocates ports, runs your setup script, and starts the server. You get a live link in the dashboard to inspect the changes an agent made - click through and see the actual running app.

**Set up recurring work with recipes.** Recipes are cron-scheduled templates that automatically create concoctions on a schedule. Want dependency updates every Sunday at 3 AM? A weekly linting pass? Create a recipe with a cron expression, enable it, and it fires on schedule. The scheduler survives restarts and recalculates next-run times on startup.

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
