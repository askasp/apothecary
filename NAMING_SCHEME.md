# Apothecary Naming Scheme

> An **apothecary** brews **concoctions** from **ingredients**. **Brewers** do the work.

---

## The Four Domain Names

| Concept | Apothecary Name | Current Code | What It Is |
|---|---|---|---|
| The application | **Apothecary** | `Apothecary` | The shop where concoctions are brewed. Already named. |
| Unit of work / PR | **Concoction** | worktree concept | A self-contained piece of work with its own git worktree. Multiple ingredients combine into one concoction. |
| Step within a concoction | **Ingredient** | `Bead` | One part of a concoction — a specific step or sub-task. Ingredients can depend on each other. |
| Claude Code agent | **Brewer** | `AgentWorker` | Takes a concoction's recipe, gathers the ingredients, and does the actual brewing. |

These four names are the entire naming scheme. Supervisors, registries, and other OTP infrastructure keep standard Elixir naming.

---

## What Gets Renamed

Only domain structs and their direct modules:

| Current Module | New Module | Why |
|---|---|---|
| `Apothecary.Bead` | `Apothecary.Ingredient` | Domain struct: a step in a concoction |
| `Apothecary.Beads` | `Apothecary.Ingredients` | Interface module for managing ingredients |
| `Apothecary.AgentWorker` | `Apothecary.Brewer` | Domain module: the Claude agent process |
| `Apothecary.AgentState` | `Apothecary.BrewerState` | State struct for a brewer |
| *(new struct)* | `Apothecary.Concoction` | Domain struct: a unit of work / PR |

## What Stays the Same

Supervisors, registries, GenServers, and utilities are standard Elixir/OTP patterns — good naming already:

| Module | Role | Why It Stays |
|---|---|---|
| `Apothecary.AgentSupervisor` | DynamicSupervisor for brewers | Supervisor — standard Elixir naming |
| `Apothecary.Dispatcher` | Coordinates work assignment | Coordination pattern, not a domain concept |
| `Apothecary.WorktreeManager` | Git worktree lifecycle | Manages the technical git concern, not the domain concept |
| `Apothecary.Poller` | Polls bd CLI for state | Infrastructure (may go away with Mnesia migration) |
| `Apothecary.CLI` | Shell command runner | Utility |
| `Apothecary.Git` | Git operations | Utility |
| `Apothecary.Startup` | Boot-time setup | Utility |
| `Apothecary.Application` | OTP application | Standard OTP |
| `Apothecary.PubSub` | Phoenix PubSub | Standard Phoenix |

---

## How It Maps

### Concoctions (new — currently just worktree paths)

A concoction is a unit of work that becomes a PR. Each gets its own isolated git worktree. Currently there's no `Worktree` struct — the concept lives in `WorktreeManager` state and `Dispatcher` tracking. Adding `Apothecary.Concoction` gives this a proper struct.

```
Concoction = recipe + ingredients + isolated workspace
Currently   = title  + beads       + git worktree path
```

- ID prefix: `wt-`
- Statuses: `open` → `in_progress` → `done` (or `blocked`)
- Done when all ingredients are combined and the result is committed

### Ingredients (currently Beads)

An ingredient is a single step needed to complete a concoction. They can depend on each other — you prepare the base before adding the active compound.

```
Ingredient = one step in the recipe
Bead       = one task from the bd CLI
```

- ID prefix: `t-`
- Ordered by priority and dependencies
- Created by brewers when they decompose complex concoctions
- Renaming `Bead` → `Ingredient` also removes the external-tool-specific naming

### Brewers (currently AgentWorkers)

A brewer is a Claude Code process working in a worktree. The dispatcher assigns concoctions to available brewers. One concoction per brewer at a time.

```
Brewer      = Claude Code process + worktree assignment
AgentWorker = GenServer + Port + state tracking
```

- States: `idle` → `starting` → `working` (or `error`)
- Managed by `AgentSupervisor` (DynamicSupervisor — keeps its name)

---

## PubSub Topics

| Current Topic | New Topic |
|---|---|
| `"beads:updates"` | `"ingredients:updates"` |
| `"agent:#{id}"` | `"brewer:#{id}"` |
| `"dispatcher:updates"` | `"dispatcher:updates"` (stays) |

## UI Labels

Dashboard headings and card labels should use the themed names:

- "Concoctions" instead of "Worktrees" or "Tasks"
- "Ingredients" instead of "Beads" or "Sub-tasks"
- "Brewers" instead of "Agents"

---

## Glossary

| Term | Meaning |
|---|---|
| **Apothecary** | The application — the shop where concoctions are brewed |
| **Concoction** | A unit of work (worktree + PR), composed of ingredients |
| **Ingredient** | A single step/task within a concoction |
| **Brewer** | A Claude Code agent that works on concoctions |
| **Recipe** | The set of ingredients needed for a concoction (implicit, not a separate struct) |

---

## Adoption Order

1. **Structs** — Add `Concoction`, rename `Bead` → `Ingredient`, `AgentState` → `BrewerState`.
2. **Agent module** — Rename `AgentWorker` → `Brewer`.
3. **Interface module** — Rename `Beads` → `Ingredients` (or replace with Mnesia-backed manager).
4. **UI labels** — Update dashboard headings and card labels.
5. **PubSub topics** — Update topic strings to match new names.
