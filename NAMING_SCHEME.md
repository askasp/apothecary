# Apothecary Naming Scheme

> *A thematic naming guide mapping every system element to its counterpart in a traditional apothecary shop.*

## The Metaphor

An **apothecary** is a historical pharmacist's workshop — a place where prescriptions arrive, ingredients are sourced from gardens and vaults, apprentices compound remedies under the pharmacist's direction, and a herald announces when each preparation is ready. This maps remarkably well onto a BEAM-orchestrated AI agent swarm.

---

## Core Architecture

| Current Name | Apothecary Name | Role | Rationale |
|---|---|---|---|
| `Apothecary` (app) | **Apothecary** | The application itself | The shop. Already perfectly named. |
| `Application` | **Shop** | OTP supervision tree root | Opening the shop starts all the processes within it. |
| `Startup` | **Opening** | Environment validation & init | The morning ritual — checking supplies, unlocking the door, making sure everything is in order before the first customer. |

## People & Roles

| Current Name | Apothecary Name | Role | Rationale |
|---|---|---|---|
| `Dispatcher` | **Pharmacist** | Assigns work to agents | The pharmacist reads incoming prescriptions and decides which apprentice should compound each one. The expert coordinator. |
| `AgentWorker` | **Apprentice** | Spawns & manages a Claude process | Apprentices do the hands-on work — grinding, mixing, brewing. Each apprentice works on one prescription at a time. |
| `AgentSupervisor` | **Guild** | DynamicSupervisor for workers | The guild oversees all apprentices, can admit new ones or retire them, and ensures the workshop is never left unattended. |
| `AgentState` | **Credentials** | Struct tracking agent state | An apprentice's credentials — their ID, current assignment, status, and when they started. |

## Work Units

| Current Name | Apothecary Name | Role | Rationale |
|---|---|---|---|
| `Worktree` (struct) | **Prescription** | A unit of work / future PR | A prescription arrives from the physician (user). It specifies what remedy to prepare. Each prescription gets its own workbench (git worktree). |
| `Task` (struct) | **Preparation** | A step within a worktree | Each prescription may require multiple preparations — one for the base, one for the active ingredient, one for the finishing. Ordered steps to fulfill the prescription. |
| `Bead` (struct) | **Order Slip** | Legacy task struct (bd CLI) | The paper slip from the old ordering system. Being replaced by the Formulary. |

## State & Storage

| Current Name | Apothecary Name | Role | Rationale |
|---|---|---|---|
| `Store` | **Vault** | Mnesia initialization | The locked vault where all records and precious materials are kept. Disc-backed (in dev) like a proper strongbox. |
| `TaskManager` | **Formulary** | CRUD for worktrees & tasks | The formulary is the master reference book — every known prescription, preparation, and their relationships are catalogued here. |
| Mnesia tables | **Ledgers** | `apothecary_worktrees`, `apothecary_tasks` | The physical ledger books inside the vault. One for prescriptions, one for preparations. |

## Infrastructure & Tools

| Current Name | Apothecary Name | Role | Rationale |
|---|---|---|---|
| `WorktreeManager` | **Herbalist** | Git worktree lifecycle | The herbalist tends the gardens — growing isolated plots (worktrees) where each prescription's ingredients are cultivated without cross-contamination. |
| `Poller` | **Sentinel** | Periodic state polling | The sentinel watches the gates, regularly checking for new arrivals and changes in the outside world. |
| `CLI` | **Mortar** | Shell command execution | The mortar (and pestle) — the most fundamental tool. Every physical act of grinding and mixing goes through it. |
| `Git` | **Chronicle** | Git operations wrapper | The chronicle records all history — every change, every branch, every merge. The shop's version-controlled memory. |
| `Beads` | **Materia Medica** | Interface to bd CLI | The materia medica is an external reference catalog of all known substances and their properties. Being superseded by the internal Formulary. |

## Communication

| Current Name | Apothecary Name | Role | Rationale |
|---|---|---|---|
| `PubSub` | **Herald** | Phoenix.PubSub message bus | The herald announces news to all who are listening. No need to check — when something happens, the herald will tell you. |
| `beads:updates` topic | `formulary:tidings` | Task state broadcasts | Tidings from the formulary — new preparations added, statuses changed. |
| `dispatcher:updates` topic | `pharmacist:directives` | Dispatch state broadcasts | The pharmacist's directives — who is assigned where, swarm state changes. |
| `agent:<id>` topic | `apprentice:<id>` | Per-agent broadcasts | Private channel to a specific apprentice — their output, state changes. |

## MCP Layer (Agent-Orchestrator Interface)

| Current Name | Apothecary Name | Role | Rationale |
|---|---|---|---|
| MCP Server | **Counter** | HTTP endpoint for agent communication | The counter is where apprentices come to receive instructions and report back. The public-facing interface of the shop. |
| MCP Tools | **Instruments** | Individual tool endpoints | The instruments laid out on the counter — each one for a specific purpose. |

### Individual MCP Tools

| Current Tool | Apothecary Name | What It Does |
|---|---|---|
| `worktree_status` | **examine_prescription** | View your prescription and all its preparations |
| `list_tasks` | **browse_formulary** | Browse the formulary for preparations |
| `get_task` | **inspect_preparation** | Examine a specific preparation in detail |
| `create_task` | **compound** | Create a new preparation (decompose work) |
| `complete_task` | **seal** | Seal a finished preparation (mark done) |
| `add_notes` | **annotate** | Add notes to the preparation log |
| `add_dependency` | **chain** | Declare that one preparation requires another first |

## Web UI (The Shop Window)

| Current Name | Apothecary Name | Role | Rationale |
|---|---|---|---|
| `DashboardLive` | **Ledger Board** | Main dashboard view | The large board at the front of the shop showing all current orders, their status, and who's working on what. |
| `AgentLive` | **Apprentice Glass** | Agent detail view | A looking glass focused on one apprentice — watch them work in real time. |
| `TaskDetailLive` | **Prescription Loupe** | Task detail view | A magnifying loupe to examine one prescription's full details, dependencies, and history. |
| `DashboardComponents` | **Signage** | UI component library | The shop's signage system — status badges, priority markers, cards. |

## Statuses

| Current Status | Apothecary Name | Meaning |
|---|---|---|
| `"open"` | **prescribed** | Work has been ordered but not yet started |
| `"in_progress"` | **compounding** | An apprentice is actively working on it |
| `"blocked"` | **awaiting ingredients** | Cannot proceed — depends on other preparations |
| `"done"` | **sealed** | Preparation complete and bottled |

### Agent Statuses

| Current Status | Apothecary Name | Meaning |
|---|---|---|
| `:idle` | **resting** | Apprentice is available for new work |
| `:starting` | **donning apron** | Apprentice is preparing their workstation |
| `:working` | **brewing** | Apprentice is actively compounding |
| `:error` | **fumbled** | Something went wrong — the potion exploded |

### Dispatcher States

| Current Status | Apothecary Name | Meaning |
|---|---|---|
| `:paused` | **shop closed** | The pharmacist is not accepting new orders |
| `:running` | **shop open** | The pharmacist is actively dispatching work |

## ID Prefixes

| Current Prefix | Apothecary Prefix | Used For |
|---|---|---|
| `wt-` | `rx-` | Prescriptions (worktrees) — Rx is the traditional pharmacy symbol |
| `t-` | `prep-` | Preparations (tasks) |
| `agent-` | `apt-` | Apprentices (agents) — short for "apprentice" |

## Configuration

| Current Config Key | Apothecary Name | Purpose |
|---|---|---|
| `:project_dir` | `:shop_location` | Where the apothecary shop is located |
| `:poll_interval` | `:sentinel_rounds` | How often the sentinel makes their rounds |
| `:bd_path` | `:materia_medica_path` | Path to the external reference catalog |
| `:claude_path` | `:apprentice_tools` | Path to the apprentice's primary tool |
| `:skip_startup` | `:skip_opening` | Skip the morning opening ritual |

## Mix Tasks

| Current Name | Apothecary Name | Purpose |
|---|---|---|
| `mix apothecary.setup` | `mix apothecary.furnish` | Set up the shop — install shelves, stock supplies, prepare the workspace |

---

## Full Glossary

| Apothecary Term | Technical Equivalent | Quick Definition |
|---|---|---|
| **Annotate** | `add_notes` MCP tool | Record observations in the preparation log |
| **Apothecary** | The application | The shop itself |
| **Apprentice** | `AgentWorker` | A worker who compounds preparations |
| **Apprentice Glass** | `AgentLive` | UI view watching one apprentice work |
| **Brewing** | Agent `:working` status | Actively compounding a preparation |
| **Browse Formulary** | `list_tasks` MCP tool | Search the formulary for preparations |
| **Chain** | `add_dependency` MCP tool | Link preparations in sequence |
| **Chronicle** | `Git` module | The historical record of all changes |
| **Compound** | `create_task` MCP tool | Create a new preparation |
| **Compounding** | `"in_progress"` status | Actively being worked on |
| **Counter** | MCP Server | Interface where apprentices receive and report work |
| **Credentials** | `AgentState` | An apprentice's current state and assignment |
| **Examine Prescription** | `worktree_status` MCP tool | View prescription overview |
| **Formulary** | `TaskManager` | Master reference of all prescriptions and preparations |
| **Fumbled** | Agent `:error` status | Something went wrong |
| **Guild** | `AgentSupervisor` | Manages all apprentices |
| **Herald** | `PubSub` | Broadcasts events to all listeners |
| **Herbalist** | `WorktreeManager` | Tends isolated gardens (git worktrees) |
| **Inspect Preparation** | `get_task` MCP tool | View one preparation's full details |
| **Instruments** | MCP Tools | Specific tools at the counter |
| **Ledger Board** | `DashboardLive` | Main status display |
| **Ledgers** | Mnesia tables | Record books in the vault |
| **Materia Medica** | `Beads` module | External reference catalog |
| **Mortar** | `CLI` module | Basic command execution tool |
| **Opening** | `Startup` | Morning validation & initialization |
| **Order Slip** | `Bead` struct | Legacy task record |
| **Pharmacist** | `Dispatcher` | Assigns prescriptions to apprentices |
| **Preparation** | `Task` struct | A single step within a prescription |
| **Prescribed** | `"open"` status | Ordered but not yet started |
| **Prescription** | `Worktree` struct | A unit of work to be fulfilled |
| **Prescription Loupe** | `TaskDetailLive` | UI for examining one prescription |
| **Resting** | Agent `:idle` status | Available for new work |
| **Seal** | `complete_task` MCP tool | Mark a preparation as finished |
| **Sealed** | `"done"` status | Complete and bottled |
| **Sentinel** | `Poller` | Watches for external changes |
| **Shop** | `Application` | The OTP supervision tree |
| **Shop Closed** | Dispatcher `:paused` | Not accepting new work |
| **Shop Open** | Dispatcher `:running` | Actively dispatching |
| **Signage** | `DashboardComponents` | UI component library |
| **Vault** | `Store` | Mnesia persistence layer |

---

## Notes on Adoption

This naming scheme can be adopted incrementally:

1. **Documentation first** — Use these names in docs, comments, and UI labels immediately
2. **UI labels** — Update dashboard text ("Agents" -> "Apprentices", "Tasks" -> "Preparations")
3. **Module renames** — The most invasive change; do in a dedicated refactor pass:
   - `AgentWorker` -> `Apprentice`
   - `AgentSupervisor` -> `Guild`
   - `Dispatcher` -> `Pharmacist`
   - etc.
4. **ID prefixes** — Update `wt-` to `rx-` and `t-` to `prep-` (requires migration)

The names that work best immediately without any code changes are the **status labels** and **UI terminology** — these can go into the dashboard today and make the whole experience more cohesive.
