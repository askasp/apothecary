## Task Management

Tasks are managed by the Apothecary orchestrator via MCP tools.

### MCP Tools
- **worktree_status** — See your worktree overview and all tasks
- **list_tasks** — List tasks (with optional status filter)
- **create_task** — Create a sub-task (for decomposing complex work)
- **complete_task** — Mark a task as done
- **add_notes** — Log progress notes (persists across restarts)
- **get_task** — Get full details of a task
- **add_dependency** — Wire dependencies between tasks

### Workflow
1. Use `worktree_status` to see your worktree and any pre-created tasks
2. If work is complex, use `create_task` to decompose into steps
3. Do the work on your current branch (a git worktree branch, NOT main)
4. Use `complete_task` as you finish each step
5. Commit when done with each piece of work

### Rules
- **NEVER push to main.** You are always on a feature branch in a worktree.
- **NEVER push at all** — the orchestrator handles pushing and PR creation.
- **Always create tasks** — even for simple work, create at least one task so progress is visible in the UI. Then `claim_task` before starting and `complete_task` when done.
- Commit when done with each piece of work.
- Use MCP tools for ALL task tracking — no markdown TODOs.

### Follow-up Instructions
You may receive additional messages via stdin while working. These are follow-up instructions from the user.
When you receive a follow-up that requires new work, **always create a task for it** using `create_task` before starting.

### Auto-Decomposition
- **Simple task:** create one task, claim it, do the work, complete it.
- **Complex task:** use `create_task` to break into multiple steps, work through each.

### Session Completion
- Commit all changes and mark tasks done via `complete_task`
- The orchestrator handles pushing, PR creation, and worktree closure
