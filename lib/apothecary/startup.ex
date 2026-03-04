defmodule Apothecary.Startup do
  @moduledoc """
  Validates the environment on application boot.
  Called from Application.start/2.

  In standalone mode, Apothecary boots without any project configured.
  Projects are added at runtime via the dashboard UI.
  """

  require Logger

  def run do
    check_claude_binary()
    check_gh_binary()

    Logger.info("Apothecary started (standalone mode — add projects via dashboard)")
    :ok
  end

  @doc "Validate a project directory before adding it."
  def validate_project(path) do
    expanded = Path.expand(path)

    with :ok <- validate_dir_exists(expanded),
         :ok <- validate_git_repo(expanded) do
      :ok
    end
  end

  defp validate_dir_exists(dir) do
    if File.dir?(dir), do: :ok, else: {:error, "Directory does not exist: #{dir}"}
  end

  defp validate_git_repo(dir) do
    case Apothecary.CLI.run("git", ["rev-parse", "--is-inside-work-tree"], cd: dir) do
      {:ok, _} -> :ok
      {:error, _} -> {:error, "#{dir} is not a git repository"}
    end
  end

  defp check_claude_binary do
    claude = Application.get_env(:apothecary, :claude_path, "claude")

    unless System.find_executable(claude) do
      Logger.warning(
        "'#{claude}' not found in PATH! " <>
          "The swarm WILL FAIL to spawn agents. " <>
          "Install Claude Code CLI or set :claude_path in config."
      )
    end
  end

  defp check_gh_binary do
    unless System.find_executable("gh") do
      Logger.warning(
        "gh (GitHub CLI) not found in PATH. PR creation will fail after agents finish work."
      )
    end
  end

  @doc "Returns the default CLAUDE.md content for swarm agents."
  def default_claude_md do
    """
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
    - Commit when done with each piece of work.
    - Use MCP tools for ALL task tracking — no markdown TODOs.

    ### Auto-Decomposition
    - **Small task:** just do it directly, use `complete_task` when done.
    - **Complex task:** use `create_task` to break into steps, work through each.

    ### Session Completion
    - Commit all changes and mark tasks done via `complete_task`
    - The orchestrator handles pushing, PR creation, and worktree closure
    """
  end
end
