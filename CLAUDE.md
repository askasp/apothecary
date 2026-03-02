## Ingredient Management

Ingredients are managed by the Apothecary orchestrator via MCP tools.
No external CLI tools needed for ingredient tracking.

### MCP Tools

You have these MCP tools available:
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
5. Use `add_notes` to log progress for context survival
6. Commit when done with each piece of work

### Rules
- **NEVER push to main.** You are always on a feature branch in a worktree.
- **NEVER push at all** — the orchestrator handles pushing and PR creation
- Commit when done with each piece of work
- Use MCP tools for ALL ingredient tracking — no markdown TODOs

### Auto-Decomposition
When you receive a large task, assess its complexity:

- **If the task is small and self-contained:** just do it directly.
- **If the task is complex (touches multiple files/systems):**
  1. Use `create_ingredient` for each logical step
  2. Use `add_dependency` to wire ordering if needed
  3. Work through ingredients in order, using `complete_ingredient` as you go

### Context Survival ("Land the Plane")
Your session may be interrupted at any time (crash, timeout, OOM). Notes and git history are how the next brewer rebuilds context.

- **Log progress frequently**: Call `add_notes` after each significant milestone, decision, or discovery
- **Be structured in notes**: Include what you tried, what worked/didn't, and what's next
- **Commit early, commit often**: Each commit is a recovery checkpoint — uncommitted work is lost on crash
- **Before finishing**: Write a final summary note covering what was accomplished and any remaining work

### Session Completion
- When you finish all work: commit your changes and mark ingredients done
- The orchestrator will handle pushing, PR creation, and concoction closure
