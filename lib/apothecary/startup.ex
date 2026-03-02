defmodule Apothecary.Startup do
  @moduledoc """
  Validates the environment and auto-initializes beads on application boot.
  Called from Application.start/2.
  """

  require Logger

  def run do
    project_dir = Application.get_env(:apothecary, :project_dir)

    with :ok <- validate_project_dir(project_dir),
         :ok <- validate_git_repo(project_dir),
         :ok <- check_bd_binary(),
         :ok <- check_claude_binary(),
         :ok <- maybe_init_beads(project_dir),
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

  defp validate_project_dir(nil), do: {:warn, "no project_dir configured"}

  defp validate_project_dir(dir) do
    if File.dir?(dir), do: :ok, else: {:error, "project_dir does not exist: #{dir}"}
  end

  defp validate_git_repo(dir) do
    case Apothecary.CLI.run("git", ["rev-parse", "--is-inside-work-tree"], cd: dir) do
      {:ok, _} -> :ok
      {:error, _} -> {:error, "#{dir} is not a git repository"}
    end
  end

  defp check_bd_binary do
    bd = Application.get_env(:apothecary, :bd_path, "bd")

    if System.find_executable(bd) do
      :ok
    else
      {:warn, "bd (beads) not found in PATH. Install with: npm install -g @beads/bd"}
    end
  end

  defp check_claude_binary do
    claude = Application.get_env(:apothecary, :claude_path, "claude")

    if System.find_executable(claude) do
      :ok
    else
      {:warn, "claude not found in PATH. Swarm will fail until claude CLI is available."}
    end
  end

  defp maybe_init_beads(dir) do
    bd = Application.get_env(:apothecary, :bd_path, "bd")

    unless System.find_executable(bd) do
      {:warn, "skipping beads init (bd not in PATH)"}
    else
      beads_dir = Path.join(dir, ".beads")

      if File.dir?(beads_dir) do
        Logger.debug("Beads already initialized in #{dir}")
        :ok
      else
        Logger.info("Initializing beads in #{dir}...")

        case Apothecary.CLI.run(bd, ["init", "--quiet"], cd: dir) do
          {:ok, _} ->
            Logger.info("Beads initialized successfully")
            :ok

          {:error, {_, msg}} ->
            {:warn, "beads init failed: #{msg}"}
        end
      end
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
    ## Issue Tracking

    We use **beads** (`bd`) for all task tracking. Always use `--json` flag.

    ### Workflow
    1. On session start: check `bd ready --json` for available tasks
    2. Do the work on your current branch (a git worktree branch, NOT main)
    3. When done: commit, push your branch
    4. Use `bd update <id> --notes "..."` to log progress

    ### Rules
    - **NEVER push to main.** You are always on a feature branch in a worktree.
    - **NEVER use `bd edit`** (opens $EDITOR, which you can't use).
    - Always `git push` before finishing. Unpushed work is lost.
    - Use `bd update <id> --notes "..."` to log progress for context survival.
    - If blocked: `bd update <id> --status blocked --notes "reason"`

    ### Auto-Decomposition
    When you receive a task, assess its complexity:

    - **If the task is small and self-contained:** just do it directly.
    - **If the task touches multiple files/systems, decompose it:**

      **Phase 1 — Create ALL subtasks first:**
      ```
      bd create "Subtask title" -t task -p 1 --parent <parent-id> --json
      ```

      **Phase 2 — Wire ALL dependencies IMMEDIATELY:**
      ```
      bd dep add <blocked_id> <blocker_id>
      ```

      **Phase 3 — Verify:**
      ```
      bd dep tree <parent-id>
      bd ready --json
      ```

      **Phase 4 — Start working** on the first ready subtask.

    ### PR Workflow
    - After completing work, always create a PR:
      `gh pr create --base main --head $(git branch --show-current) --fill`
    - Include the bead ID in the PR title
    - Do NOT delete your branch after creating the PR
    """
  end
end
