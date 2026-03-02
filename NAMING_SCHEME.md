# Apothecary Naming Scheme

> *Domain naming for the core concepts. OTP primitives (supervisors, registries, GenServers) keep their standard Elixir names.*

## The Metaphor

An **apothecary** brews concoctions from ingredients. Brewers do the work.

---

## Core Domain Names

| Concept | Apothecary Name | Current Name | What It Is |
|---|---|---|---|
| The application | **Apothecary** | `Apothecary` | Already named. The shop where concoctions are brewed. |
| Unit of work / PR | **Concoction** | `Worktree` | A concoction is what gets brewed — a self-contained piece of work with its own git worktree. Multiple ingredients combine into one concoction. |
| Step within a concoction | **Ingredient** | `Task` | An ingredient is one part of a concoction — a specific step or sub-task. A concoction may need many ingredients combined in order. |
| Agent worker | **Brewer** | `AgentWorker` | A brewer takes a concoction's recipe, gathers the ingredients, and does the actual brewing (runs Claude Code in a worktree). |

## What Stays the Same

Standard Elixir/OTP naming is good naming. These keep their current names:

- **Supervisors** (`AgentSupervisor`, `DynamicSupervisor`) — standard OTP
- **Registries** — standard OTP
- **GenServers** (`Store`, `Dispatcher`, `TaskManager`) — standard OTP pattern
- **PubSub** — standard Phoenix
- **Application** — standard OTP

The apothecary names apply to the **domain concepts**, not the infrastructure.

## How It Maps

### Concoctions (Worktrees)

A concoction is a unit of work that will become a PR. Each concoction gets its own isolated git worktree where a brewer can work without interfering with others.

```
Concoction = recipe + ingredients + isolated workspace
Worktree   = title  + tasks       + git worktree
```

- ID prefix: `wt-` (or consider `cx-` for concoction)
- Statuses: `open` / `in_progress` / `blocked` / `done`
- A concoction is "done" when all its ingredients have been combined and the result is committed.

### Ingredients (Tasks)

An ingredient is a single step needed to complete a concoction. Ingredients can depend on other ingredients (you need to prepare the base before adding the active compound).

```
Ingredient = one step in the recipe
Task       = one step in the worktree
```

- ID prefix: `t-` (or consider `ig-` for ingredient)
- Ordered by priority and dependencies
- Created by brewers when they decompose complex concoctions

### Brewers (Agents)

A brewer is a Claude Code process running in a worktree. The dispatcher assigns concoctions to available brewers. Each brewer works on one concoction at a time.

```
Brewer = Claude Code process + worktree assignment
Agent  = AgentWorker + port + watchdog
```

- Brewer states: `idle` / `starting` / `working` / `error`
- Managed by the AgentSupervisor (standard DynamicSupervisor)

## MCP Tools

The MCP tools are the brewer's interface to the apothecary. These could be renamed to fit the theme:

| Current Tool | Themed Name | What It Does |
|---|---|---|
| `worktree_status` | `concoction_status` | View the concoction and all its ingredients |
| `list_tasks` | `list_ingredients` | List ingredients (with optional status filter) |
| `get_task` | `get_ingredient` | Examine a specific ingredient |
| `create_task` | `add_ingredient` | Add a new ingredient to the concoction |
| `complete_task` | `finish_ingredient` | Mark an ingredient as done |
| `add_notes` | `add_notes` | Log progress notes (fine as-is) |
| `add_dependency` | `add_dependency` | Wire ingredient ordering (fine as-is) |

## UI Labels

The dashboard can use the themed names in its UI:

- "Worktrees" section heading -> "Concoctions"
- "Tasks" section heading -> "Ingredients"
- "Agents" section heading -> "Brewers"
- Status badges and cards can use the same terminology

## Module Rename Plan

Only the domain modules need renaming. OTP wrappers keep their names.

| Current Module | New Module | Notes |
|---|---|---|
| `Apothecary.Worktree` | `Apothecary.Concoction` | Struct + Mnesia record helpers |
| `Apothecary.Task` | `Apothecary.Ingredient` | Struct + Mnesia record helpers (also eliminates `Elixir.Task` name conflict) |
| `Apothecary.AgentWorker` | `Apothecary.Brewer` | Port-based Claude process |
| `Apothecary.WorktreeManager` | `Apothecary.ConcoctionManager` | Git worktree lifecycle |

Modules that stay as they are:

| Module | Why |
|---|---|
| `Apothecary.Store` | GenServer managing Mnesia — standard pattern |
| `Apothecary.TaskManager` | GenServer for CRUD — could become `Apothecary.RecipeBook` but not required |
| `Apothecary.Dispatcher` | GenServer for dispatch — standard pattern |
| `Apothecary.AgentSupervisor` | DynamicSupervisor — standard OTP |
| `Apothecary.CLI` | Utility module — no domain concept |
| `Apothecary.MCP.Server` | Infrastructure — standard naming |

## Mnesia Tables

| Current Table | New Table |
|---|---|
| `apothecary_worktrees` | `apothecary_concoctions` |
| `apothecary_tasks` | `apothecary_ingredients` |

## Glossary

| Term | Meaning |
|---|---|
| **Apothecary** | The application — the shop where concoctions are brewed |
| **Concoction** | A unit of work (worktree + PR). Composed of ingredients. |
| **Ingredient** | A single step/task within a concoction |
| **Brewer** | A Claude Code agent that works on concoctions |
| **Recipe** | The set of ingredients needed for a concoction (implicit, not a separate struct) |

---

## Adoption

1. **UI labels first** — Update dashboard headings and card labels. Zero code risk.
2. **MCP tool names** — Rename the 5 tools that map to domain concepts. Agents will adapt.
3. **Structs and modules** — Rename `Worktree` -> `Concoction`, `Task` -> `Ingredient`, `AgentWorker` -> `Brewer`. This also fixes the `Elixir.Task` naming conflict.
4. **Mnesia tables** — Rename tables with a migration. Do last since it touches persistence.
