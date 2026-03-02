# Apothecary Naming Scheme

> An **apothecary** brews **concoctions** from **ingredients**. **Brewers** do the work.

---

## The Four Domain Names

| Concept | Apothecary Name | Currently In Code | What It Is |
|---|---|---|---|
| The application | **Apothecary** | `Apothecary` | The shop where everything happens. Already named. |
| Unit of work / PR | **Concoction** | Worktrees (`WorktreeManager`, `Dispatcher` state) | A self-contained piece of work with its own git worktree. Multiple ingredients combine into one concoction. |
| Task / step within a concoction | **Ingredient** | `Bead` / `Beads` | A single task or step. Ingredients can depend on each other — you prepare the base before adding the active compound. |
| Claude Code agent | **Brewer** | `AgentWorker` / `AgentState` | Takes a concoction, gathers the ingredients, and does the actual brewing. |

These four names are the entire naming scheme. Everything else — supervisors, registries, dispatchers, utilities — keeps standard Elixir/OTP naming.

---

## What Stays the Same

Supervisors, registries, and infrastructure modules use idiomatic Elixir naming. No reason to theme them:

- `Apothecary.AgentSupervisor` — DynamicSupervisor for brewers
- `Apothecary.Dispatcher` — assigns concoctions to available brewers
- `Apothecary.WorktreeManager` — git worktree lifecycle (the technical git layer under concoctions)
- `Apothecary.Poller` — polls for state changes
- `Apothecary.CLI`, `Apothecary.Git`, `Apothecary.Startup` — utilities
- `Apothecary.Application`, `Apothecary.PubSub` — standard OTP/Phoenix

---

## How It Maps

### Concoctions (currently worktrees)

A concoction is a unit of work that becomes a PR. Each gets its own isolated git worktree.

```
Concoction = recipe + ingredients + isolated workspace
Currently  = title  + tasks      + git worktree path
```

- ID prefix: `wt-`
- Statuses: `open` → `in_progress` → `done` (or `blocked`)
- Done when all ingredients are combined and the result is committed

### Ingredients (currently tasks / beads)

An ingredient is a single task needed to complete a concoction. They can depend on each other.

```
Ingredient = one step in the recipe
Currently  = one task (Bead struct in code)
```

- ID prefix: `t-`
- Ordered by priority and dependencies
- Created by brewers when they decompose complex concoctions

### Brewers (currently agents)

A brewer is a Claude Code process working on a concoction. The dispatcher assigns concoctions to available brewers. One concoction per brewer at a time.

```
Brewer     = Claude Code process + concoction assignment
Currently  = AgentWorker GenServer + Port
```

- States: `idle` → `starting` → `working` (or `error`)
- Managed by `AgentSupervisor` (DynamicSupervisor — keeps its name)

---

## Module Renames

Only domain structs and their direct modules get renamed:

| Current | New | Why |
|---|---|---|
| `Apothecary.Bead` | `Apothecary.Ingredient` | Domain struct: a task/step in a concoction |
| `Apothecary.Beads` | `Apothecary.Ingredients` | Interface module for managing ingredients |
| `Apothecary.AgentWorker` | `Apothecary.Brewer` | Domain module: the Claude agent process |
| `Apothecary.AgentState` | `Apothecary.BrewerState` | State struct for a brewer |
| *(new)* | `Apothecary.Concoction` | Domain struct: a unit of work / PR |

---

## Glossary

| Term | Meaning |
|---|---|
| **Apothecary** | The application — the shop where concoctions are brewed |
| **Concoction** | A unit of work (worktree + PR), composed of ingredients |
| **Ingredient** | A single task within a concoction |
| **Brewer** | A Claude Code agent that works on concoctions |
| **Recipe** | The set of ingredients needed for a concoction (implicit, not a separate struct) |
