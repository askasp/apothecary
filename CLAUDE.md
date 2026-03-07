## Task Management

Tasks are managed by the Apothecary orchestrator via MCP tools.
No external CLI tools needed for task tracking.

### MCP Tools

You have these MCP tools available:
- **worktree_status** — See your worktree overview and all tasks
- **list_tasks** — List tasks (with optional status filter)
- **create_task** — Create a sub-task (for decomposing complex work)
- **claim_task** — Claim a task (sets it to in_progress) before you start working on it
- **complete_task** — Mark a task as done
- **add_notes** — Log progress notes (persists across restarts)
- **get_task** — Get full details of a task
- **add_dependency** — Wire dependencies between tasks
- **get_project_context** — Get shared project knowledge saved by other agents
- **save_project_context** — Save project knowledge for other agents to reuse

### Workflow
1. Use `worktree_status` to see your worktree and any pre-created tasks
2. If work is complex, use `create_task` to decompose into steps
3. **Use `claim_task` before starting each task** — this shows progress in the UI
4. Do the work on your current branch (a git worktree branch, NOT main)
5. Use `complete_task` as you finish each step
6. Use `add_notes` to log progress for context survival
7. Commit when done with each piece of work

### Rules
- **NEVER push to main.** You are always on a feature branch in a worktree.
- **NEVER push at all** — the orchestrator handles pushing and PR creation
- **Claim → Work → Complete**: For each task, call `claim_task` first, do the work, then `complete_task`. Work through tasks in listed order (by priority, then creation order). After completing a task, immediately claim the next one.
- Commit when done with each piece of work
- Use MCP tools for ALL task tracking — no markdown TODOs

### Auto-Decomposition
When you receive a task, **always create at least one task** so progress is visible in the UI.

- **If the task is small and self-contained:** create one task, claim it, do the work, complete it.
- **If the task is complex (touches multiple files/systems):**
  1. **First use `list_tasks` to read ALL existing tasks** for the worktree — the user may have manually added tasks that overlap with what you plan to create. Skip creating duplicates.
  2. Use `create_task` for each logical step that doesn't already exist
  3. Use `add_dependency` to wire ordering if needed
  4. Work through tasks in order, using `complete_task` as you go

### Context Survival ("Land the Plane")
Your session may be interrupted at any time (crash, timeout, OOM). Notes and git history are how the next brewer rebuilds context.

- **Log progress frequently**: Call `add_notes` after each significant milestone, decision, or discovery
- **Be structured in notes**: Include what you tried, what worked/didn't, and what's next
- **Commit early, commit often**: Each commit is a recovery checkpoint — uncommitted work is lost on crash
- **Before finishing**: Write a final summary note covering what was accomplished and any remaining work

### Session Completion
- When you finish all work: commit your changes and mark tasks done
- The orchestrator will handle pushing, PR creation, and worktree closure
