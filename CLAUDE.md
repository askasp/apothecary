## Task Management

Tasks are managed by the Apothecary orchestrator via MCP tools.
No external CLI tools needed for task tracking.

### MCP Tools

You have these MCP tools available:
- **worktree_status** — See your worktree overview and all tasks
- **list_tasks** — List tasks (with optional status filter)
- **create_task** — Create a sub-task (for decomposing complex work)
- **complete_task** — Mark a task as done
- **add_notes** — Log progress notes (persists across restarts)
- **get_task** — Get full details of a task
- **add_dependency** — Wire dependencies between tasks
- **get_project_context** — Get shared project knowledge saved by other agents
- **save_project_context** — Save project knowledge for other agents to reuse

### Workflow
1. Use `worktree_status` to see your worktree and any pre-created tasks
2. If work is complex, use `create_task` to decompose into steps
3. Do the work on your current branch (a git worktree branch, NOT main)
4. Use `complete_task` as you finish each step
5. Use `add_notes` to log progress for context survival
6. Commit when done with each piece of work

### Rules
- **NEVER push to main.** You are always on a feature branch in a worktree.
- **NEVER push at all** — the orchestrator handles pushing and PR creation
- Commit when done with each piece of work
- Use MCP tools for ALL task tracking — no markdown TODOs

### Auto-Decomposition
When you receive a large task, assess its complexity:

- **If the task is small and self-contained:** just do it directly.
- **If the task is complex (touches multiple files/systems):**
  1. Use `create_task` for each logical step
  2. Use `add_dependency` to wire ordering if needed
  3. Work through tasks in order, using `complete_task` as you go

### Context Survival ("Land the Plane")
Your session may be interrupted at any time (crash, timeout, OOM). Notes and git history are how the next brewer rebuilds context.

- **Log progress frequently**: Call `add_notes` after each significant milestone, decision, or discovery
- **Be structured in notes**: Include what you tried, what worked/didn't, and what's next
- **Commit early, commit often**: Each commit is a recovery checkpoint — uncommitted work is lost on crash
- **Before finishing**: Write a final summary note covering what was accomplished and any remaining work

### Session Completion
- When you finish all work: commit your changes and mark tasks done
- The orchestrator will handle pushing, PR creation, and worktree closure
