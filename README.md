# Apothecary
## A claude orchestration IDE

I tried running an entire [Gas Town](https://github.com/steveyegge/gastown). Turns out that's a lot. But an apothecary? That I can manage.

Apothecary is a small Elixir app that runs multiple Claude Code agents in parallel. You give it work, it spins up agents in isolated git worktrees, they do the coding, and PRs come out the other end. It's inspired by [Beads](https://github.com/steveyegge/beads) and Gas Town, but uses the BEAM for process supervision — so when an agent crashes, it just gets restarted. Agent contiously write notes on what the discover that are recovered on a crash restard.


## How it works

1. You create a **worktree** — it gets its own git worktree branch, completely isolated
2. An idle agent picks it up automatically
3. Claude Code spawns in the worktree, reads the task, and starts coding
4. If the work is complex, the agent breaks it into **tasks** (sub-steps) on its own
5. When done, the branch gets pushed and a PR opens
6. If reviewers request changes, an agent gets re-dispatched to address them

The whole thing is reactive — no polling. State changes propagate instantly and idle agents pick up work as soon as it appears.

## What you can do with it

### Run a swarm overnight, wake up to PRs

Create a batch of worktrees before bed — refactors, bug fixes, feature stubs, whatever. The agents work through the queue in parallel while you sleep. In the morning you've got a stack of PRs to review instead of a pile of tickets to start.

### Scale agents up or down on the fly

The dashboard lets you set anywhere from 1 to 10 parallel agents. Running on a beefy machine? Crank it up. Want to keep things calm? Run one at a time. You can change the count while agents are already working — new ones spin up, extras wind down gracefully.

### Talk to agents while they work

Select a worktree that's being worked on and type into the input bar — it goes straight to the agent's stdin.

### Preview what agents built before merging

Drop a `.apothecary/preview.yml` in your repo and any worktree can spin up a live dev server right in its branch. Apothecary allocates ports so multiple previews don't conflict. You get clickable links in the dashboard — one click and you're looking at the actual running app the agent just built. No more "looks fine in the diff, let me check it out locally."

### Review diffs without leaving the dashboard

Press `d` on any worktree and get a full-screen diff viewer — file list on the left, syntax-colored diff on the right. Files are color-coded: green for additions, yellow for mixed changes, red for deletions. Navigate with `j`/`k`, close with `Esc`. It's like a mini lazygit right in your browser.

### Set up recurring work with recipes

Recipes are cron-scheduled templates that automatically create worktrees. Want dependency updates every Sunday at 3 AM? A weekly linting pass? Create a recipe with a cron expression, enable it, and it fires on schedule. The scheduler survives restarts and recalculates next-run times on startup. Set it and forget it.

### Automatic PR revision cycles

When a reviewer requests changes on a PR, Apothecary notices (it polls GitHub every 60 seconds), marks the worktree as needing revision, and dispatches an agent to go fix it. The agent reads the review comments and pushes new commits to the existing PR. You don't have to do anything — just leave your review and walk away.

## What keeps it running

Agents crash. They hang. They run out of memory. That's fine. Two things handle it:

**Watchdog** — Each agent has a 5-minute silence timer. If Claude stops producing output for that long, the watchdog kills the process, logs the last 30 lines of output, and releases the worktree back to the pool. An idle agent picks it up and tries again.

**Notes** — Agents log progress notes as they work: what they tried, what worked, key decisions. These notes are stored in Mnesia and get included in the prompt when the next agent picks up the worktree. So if an agent crashes halfway through, the replacement doesn't start from scratch — it reads what happened and continues. Crash diagnostics get written to notes automatically too.

Between the two, the system is self-healing. Stuck agents get recycled, and context survives across restarts. You can walk away and it sorts itself out.

## The dashboard

The dashboard is a Phoenix LiveView app — real-time updates, no page refreshes, and entirely keyboard-driven if you want it to be.

Worktrees are grouped in the left panel as a tree:

| Group | What's in it |
|-------|-------------|
| **Brewing** | Currently being worked on by an agent |
| **Reviewing** | PR is open, under review |
| **Queued** | Ready and waiting for an agent |
| **Bottled** | Done and merged |

Each entry shows the title and which agent is working on it. Select a worktree to see its tasks, progress, agent notes, and live output stream in the right panel. A preview of your app runs inline — you can see what the agent built without leaving the dashboard.

The input bar is context-sensitive:
- Plain text creates a new worktree
- If you have a worktree selected, typing adds a task to it
- If an agent is working on the selected worktree, your text goes directly to the agent
- Prefix with `?` to ask a question about the codebase

### Keyboard shortcuts

The whole UI is keyboard-navigable. Press `?` for the full list, but the highlights:

| Key | What it does |
|-----|-------------|
| `j` / `k` | Navigate worktrees |
| `Enter` | Open detail panel |
| `s` | Start/stop the swarm |
| `+` / `-` | More/fewer agents |
| `d` | Diff viewer |
| `D` | Toggle preview server |
| `/` or `c` | Focus input |
| `1-4` | Jump to group |
| `q` | Requeue selected |
| `m` | Merge PR |
| `?` | Show all shortcuts |

## The naming

| Term | What it is |
|------|-----------|
| **Worktree** | A unit of work — one git worktree, one branch, one PR (`wt-*` IDs) |
| **Task** | A step within a worktree (`t-*` IDs) |
| **Agent** | A Claude Code agent process |
| **Recipe** | A cron-scheduled template for recurring worktrees |

## Why Elixir

Each agent is a GenServer under a DynamicSupervisor. Agent crashes are isolated — one going down doesn't affect the others. Mnesia handles all the state so there's no external database to set up. Phoenix PubSub makes the dispatch reactive, and LiveView gives you a real-time dashboard without writing any JavaScript.

The BEAM is good at running lots of concurrent processes that talk to each other and occasionally fall over. That's exactly what this is.

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
command: "npm run dev"
port_count: 2
setup: "npm install"
ports:
  - name: web
    offset: 0
  - name: vite-hmr
    offset: 1
```

Apothecary injects a `BASE_PORT` env variable so your dev server knows which port to bind to.

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
