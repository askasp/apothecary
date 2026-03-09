# Apothecary Naming Scheme

> An **apothecary** manages **worktrees** composed of **tasks**. **Brewers** do the work.

---

## The Four Domain Names

| Concept | Apothecary Name | Module | What It Is |
|---|---|---|---|
| The application | **Apothecary** | `Apothecary` | The shop where everything happens. |
| Unit of work / PR | **Worktree** | `Apothecary.Worktree` | A self-contained piece of work with its own git worktree. Multiple tasks combine into one worktree. |
| Task / step within a worktree | **Task** | `Apothecary.Task` | A single task or step. Tasks can depend on each other. |
| Claude Code agent | **Brewer** | `Apothecary.Brewer` | Takes a worktree, works through the tasks, and does the actual brewing. |

These four names are the entire naming scheme. Everything else — supervisors, registries, dispatchers, utilities — keeps standard Elixir/OTP naming.

---

## What Stays the Same

Supervisors, registries, and infrastructure modules use idiomatic Elixir naming. No reason to theme them:

- `Apothecary.BrewerSupervisor` — DynamicSupervisor for brewers
- `Apothecary.Dispatcher` — assigns worktrees to available brewers
- `Apothecary.WorktreeManager` — git worktree lifecycle (the technical git layer under worktrees)
- `Apothecary.CLI`, `Apothecary.Git`, `Apothecary.Startup` — utilities
- `Apothecary.Application`, `Apothecary.PubSub` — standard OTP/Phoenix

---

## How It Maps

### Worktrees

A worktree is a unit of work that becomes a PR. Each gets its own isolated git worktree.

```
Worktree = title + tasks + isolated workspace
         = title + tasks + git worktree path
```

- ID prefix: `wt-`
- Statuses: `open` → `in_progress` → `done` (or `blocked`)
- Done when all tasks are completed and the result is committed

### Tasks

A task is a single step needed to complete a worktree. They can depend on each other.

```
Task = one step in the worktree
```

- ID prefix: `t-`
- Ordered by priority and dependencies
- Created by brewers when they decompose complex worktrees

### Brewers

A brewer is a Claude Code process working on a worktree. The dispatcher assigns worktrees to available brewers. One worktree per brewer at a time.

```
Brewer = Claude Code process + worktree assignment
       = Apothecary.Brewer GenServer + Port
```

- States: `idle` → `starting` → `working` (or `error`)
- Managed by `BrewerSupervisor` (DynamicSupervisor)

---

## Module Map

| Module | Purpose |
|---|---|
| `Apothecary.Worktree` | Domain struct: a unit of work / PR |
| `Apothecary.Task` | Domain struct: a task/step in a worktree |
| `Apothecary.Worktrees` | Interface module for managing worktrees + tasks |
| `Apothecary.Brewer` | Domain module: the Claude agent process |
| `Apothecary.BrewerState` | State struct for a brewer |

---

## Glossary

| Term | Meaning |
|---|---|
| **Apothecary** | The application — the shop where worktrees are brewed |
| **Worktree** | A unit of work (git worktree + PR), composed of tasks |
| **Task** | A single task within a worktree |
| **Brewer** | A Claude Code agent that works on worktrees |
| **Recipe** | The set of tasks needed for a worktree (implicit, not a separate struct) |
