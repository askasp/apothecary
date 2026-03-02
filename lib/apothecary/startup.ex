defmodule Apothecary.Startup do
  @moduledoc """
  Validates the environment on application boot.
  Called from Application.start/2.
  """

  require Logger

  def run do
    project_dir = Application.get_env(:apothecary, :project_dir) || File.cwd!()
    Application.put_env(:apothecary, :project_dir, project_dir)

    with :ok <- validate_project_dir(project_dir),
         :ok <- validate_git_repo(project_dir),
         :ok <- check_claude_binary(),
         :ok <- check_gh_binary(),
         :ok <- maybe_write_claude_md(project_dir) do
      Logger.info("Apothecary started for project: #{project_dir}")
      :ok
    else
      {:warn, msg} ->
        Logger.warning("Apothecary: #{msg}")
        :ok

      {:error, msg} ->
        Logger.error("Apothecary startup: #{msg}")
        :ok
    end
  end

  defp validate_project_dir(dir) do
    if File.dir?(dir), do: :ok, else: {:error, "project_dir does not exist: #{dir}"}
  end

  defp validate_git_repo(dir) do
    case Apothecary.CLI.run("git", ["rev-parse", "--is-inside-work-tree"], cd: dir) do
      {:ok, _} -> :ok
      {:error, _} -> {:error, "#{dir} is not a git repository"}
    end
  end

  defp check_claude_binary do
    claude = Application.get_env(:apothecary, :claude_path, "claude")

    if System.find_executable(claude) do
      :ok
    else
      {:warn,
       "WARNING: '#{claude}' not found in PATH! " <>
         "The swarm WILL FAIL to spawn agents. " <>
         "Install Claude Code CLI or set :claude_path in config."}
    end
  end

  defp check_gh_binary do
    if System.find_executable("gh") do
      :ok
    else
      {:warn, "gh (GitHub CLI) not found in PATH. PR creation will fail after agents finish work."}
    end
  end

  defp maybe_write_claude_md(dir) do
    claude_md_path = Path.join(dir, "CLAUDE.md")

    if File.exists?(claude_md_path) do
      :ok
    else
      Logger.info("Writing default CLAUDE.md to #{dir}")
      File.write!(claude_md_path, default_claude_md())
      :ok
    end
  end

  @doc "Returns the default CLAUDE.md content for swarm agents."
  def default_claude_md do
    """
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
    """
  end
end
