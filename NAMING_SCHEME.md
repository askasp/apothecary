# Apothecary Naming Scheme

> *Four domain names. Everything else keeps standard Elixir/OTP naming.*

## The Metaphor

An **apothecary** brews **concoctions** from **ingredients**. **Brewers** do the work.

---

## The Four Domain Names

| Concept | Apothecary Name | Current Code Name | What It Is |
|---|---|---|---|
| The application | **Apothecary** | `Apothecary` | The shop where concoctions are brewed. Already named. |
| Unit of work / PR | **Concoction** | `Worktree` | A self-contained piece of work with its own git worktree. Multiple ingredients combine into one concoction. |
| Step within a concoction | **Ingredient** | `Task` | One part of a concoction — a specific step or sub-task. Ingredients can depend on each other. |
| Claude Code agent | **Brewer** | `AgentWorker` | Takes a concoction's recipe, gathers the ingredients, and does the actual brewing. |

These four names are the entire naming scheme. Everything else stays as-is.

## What Stays the Same

Supervisors, registries, and GenServers are standard Elixir/OTP patterns — good naming already. No need to rename them.

- **Supervisors** — `AgentSupervisor`, `DynamicSupervisor`
- **Registries** — standard OTP
- **GenServers** — `Store`, `Dispatcher`, `TaskManager`, `WorktreeManager`
- **PubSub** — standard Phoenix
- **Application** — standard OTP
- **CLI** — utility, not a domain concept
- **MCP.Server** — infrastructure

The apothecary names apply to **domain concepts only**, not infrastructure.

---

## How It Maps

### Concoctions (currently Worktrees)

A concoction is a unit of work that becomes a PR. Each gets its own isolated git worktree.

```
Concoction = recipe + ingredients + isolated workspace
Worktree   = title  + tasks       + git worktree
```

- ID prefix: `wt-` (kept for brevity)
- Statuses: `open` → `in_progress` → `done` (or `blocked`)
- Done when all ingredients are combined and the result is committed

### Ingredients (currently Tasks)

An ingredient is a single step needed to complete a concoction. They can depend on each other — you prepare the base before adding the active compound.

```
Ingredient = one step in the recipe
Task       = one step in the worktree
```

- ID prefix: `t-` (kept for brevity)
- Ordered by priority and dependencies
- Created by brewers when they decompose complex concoctions
- Renaming `Task` → `Ingredient` also eliminates the `Elixir.Task` name conflict

### Brewers (currently AgentWorkers)

A brewer is a Claude Code process running in a worktree. The dispatcher assigns concoctions to available brewers. One concoction per brewer at a time.

```
Brewer = Claude Code process + worktree assignment
Agent  = AgentWorker + port + watchdog
```

- States: `idle` → `starting` → `working` (or `error`)
- Managed by AgentSupervisor (standard DynamicSupervisor — keeps its name)

---

## Module Renames

Only the three domain structs get renamed:

| Current Module | New Module |
|---|---|
| `Apothecary.Worktree` | `Apothecary.Concoction` |
| `Apothecary.Task` | `Apothecary.Ingredient` |
| `Apothecary.AgentWorker` | `Apothecary.Brewer` |

Everything else (`Store`, `TaskManager`, `WorktreeManager`, `Dispatcher`, `AgentSupervisor`, `CLI`, `MCP.*`) stays as-is.

## Mnesia Tables

| Current Table | New Table |
|---|---|
| `apothecary_worktrees` | `apothecary_concoctions` |
| `apothecary_tasks` | `apothecary_ingredients` |

## UI & MCP Labels

The themed names should appear in user-facing surfaces:

- Dashboard headings: "Concoctions", "Ingredients", "Brewers"
- MCP tool names can optionally adopt the theme (e.g. `list_ingredients` instead of `list_tasks`)
- ID prefixes stay short: `wt-` and `t-`

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

1. **UI labels** — Update dashboard headings and card labels. Zero code risk.
2. **Structs and modules** — Rename `Worktree` → `Concoction`, `Task` → `Ingredient`, `AgentWorker` → `Brewer`.
3. **Mnesia tables** — Rename with a migration. Do last since it touches persistence.
4. **MCP tools** — Optional. Rename the domain-facing tools to match the theme.
