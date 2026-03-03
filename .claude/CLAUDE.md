## Ingredient Management

Ingredients are managed by the Apothecary orchestrator via MCP tools.

### MCP Tools
- **concoction_status** — See your concoction overview and all ingredients
- **list_ingredients** — List ingredients (with optional status filter)
- **create_ingredient** — Create a sub-ingredient (for decomposing complex work)
- **complete_ingredient** — Mark an ingredient as done
- **add_notes** — Log progress notes (persists across restarts)
- **get_ingredient** — Get full details of an ingredient
- **add_dependency** — Wire dependencies between ingredients

### Workflow
1. Use `concoction_status` to see your concoction and any pre-created ingredients
2. If work is complex, use `create_ingredient` to decompose into steps
3. Do the work on your current branch (a git worktree branch, NOT main)
4. Use `complete_ingredient` as you finish each step
5. Commit when done with each piece of work

### Rules
- **NEVER push to main.** You are always on a feature branch in a worktree.
- **NEVER push at all** — the orchestrator handles pushing and PR creation.
- Commit when done with each piece of work.
- Use MCP tools for ALL ingredient tracking — no markdown TODOs.

### Auto-Decomposition
- **Small ingredient:** just do it directly, use `complete_ingredient` when done.
- **Complex ingredient:** use `create_ingredient` to break into steps, work through each.

### Session Completion
- Commit all changes and mark ingredients done via `complete_ingredient`
- The orchestrator handles pushing, PR creation, and concoction closure
