defmodule Apothecary.Git do
  @moduledoc """
  Git CLI wrapper for worktree and repository inspection.

  All functions that operate on a project repository accept `project_dir`
  as an explicit parameter — no global state dependency.
  """

  alias Apothecary.CLI
  require Logger

  @doc "List all git worktrees in porcelain format."
  def list_worktrees(project_dir) do
    case CLI.run("git", ["worktree", "list", "--porcelain"], cd: project_dir) do
      {:ok, output} -> {:ok, parse_worktrees(output)}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc "Create a new worktree with a branch based on the given base branch."
  def create_worktree(project_dir, path, branch, base_branch \\ "main") do
    CLI.run("git", ["worktree", "add", "-b", branch, path, base_branch], cd: project_dir)
  end

  @doc "Remove a worktree."
  def remove_worktree(project_dir, path) do
    CLI.run("git", ["worktree", "remove", "--force", path], cd: project_dir)
  end

  @doc "Get the current branch for a worktree path."
  def current_branch(path) do
    case CLI.run("git", ["branch", "--show-current"], cd: path) do
      {:ok, branch} -> {:ok, String.trim(branch)}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc "Check if a path is inside a git repository."
  def is_repo?(path) do
    case CLI.run("git", ["rev-parse", "--is-inside-work-tree"], cd: path) do
      {:ok, "true"} -> true
      _ -> false
    end
  end

  @doc "Get the main/master branch name."
  def main_branch(project_dir) do
    case CLI.run("git", ["symbolic-ref", "refs/remotes/origin/HEAD", "--short"], cd: project_dir) do
      {:ok, ref} ->
        ref |> String.trim() |> String.split("/") |> List.last()

      {:error, _} ->
        # Fallback: check if main or master exists
        case CLI.run("git", ["rev-parse", "--verify", "main"], cd: project_dir) do
          {:ok, _} -> "main"
          _ -> "master"
        end
    end
  end

  @doc "Reset a worktree branch to the latest main."
  def reset_to_main(project_dir, worktree_path) do
    base = main_branch(project_dir)

    with {:ok, _} <- CLI.run("git", ["fetch", "origin", base], cd: worktree_path),
         {:ok, _} <- CLI.run("git", ["reset", "--hard", "origin/#{base}"], cd: worktree_path) do
      :ok
    end
  end

  @doc "Fetch latest main and merge it into the current worktree branch."
  def merge_main_into(project_dir, worktree_path) do
    base = main_branch(project_dir)

    with {:ok, _} <- CLI.run("git", ["fetch", "origin", base], cd: worktree_path),
         {:ok, _} <- CLI.run("git", ["merge", "origin/#{base}", "--no-edit"], cd: worktree_path) do
      :ok
    else
      {:error, {_code, output}} = error ->
        if merge_conflict?(output), do: {:error, {:merge_conflict, output}}, else: error

      error ->
        error
    end
  end

  @doc "Abort an in-progress merge."
  def abort_merge(worktree_path) do
    CLI.run("git", ["merge", "--abort"], cd: worktree_path)
  end

  @doc "Check if git command output indicates a merge conflict."
  def merge_conflict?(output) when is_binary(output) do
    String.contains?(output, "CONFLICT") or
      String.contains?(output, "Automatic merge failed") or
      String.contains?(output, "fix conflicts")
  end

  def merge_conflict?(_), do: false

  @doc "Extract conflicting file paths from merge conflict output."
  def conflict_files(output) when is_binary(output) do
    ~r/CONFLICT \([^)]+\): (?:Merge conflict in |[^:]+: )(.+)/
    |> Regex.scan(output)
    |> Enum.map(fn [_, file] -> String.trim(file) end)
    |> Enum.uniq()
  end

  @doc "Check if a remote named 'origin' is configured for this repo."
  def has_remote?(project_dir) do
    case CLI.run("git", ["remote"], cd: project_dir) do
      {:ok, output} -> String.contains?(output, "origin")
      {:error, _} -> false
    end
  end

  @doc """
  Merge a feature branch into main locally (no GitHub needed).

  Checks out main, merges the branch with --no-ff, then returns.
  Returns :ok or {:error, reason}.
  """
  def merge_branch(project_dir, branch) do
    base = main_branch(project_dir)

    with {:ok, _} <- CLI.run("git", ["checkout", base], cd: project_dir),
         {:ok, _} <-
           CLI.run("git", ["merge", branch, "--no-ff", "--no-edit"], cd: project_dir) do
      :ok
    else
      {:error, {_code, output}} = error ->
        if merge_conflict?(output) do
          # Abort the merge to leave the repo clean
          CLI.run("git", ["merge", "--abort"], cd: project_dir)
          {:error, {:merge_conflict, output}}
        else
          error
        end

      error ->
        error
    end
  end

  @doc "Push the current branch in a worktree to origin."
  def push_branch(worktree_path) do
    case current_branch(worktree_path) do
      {:ok, branch} ->
        CLI.run("git", ["push", "-u", "origin", branch], cd: worktree_path)

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc "Create a PR from the current branch in a worktree. Returns {:ok, pr_url} or {:error, reason}."
  def create_pr(project_dir, worktree_path, title) do
    case current_branch(worktree_path) do
      {:ok, branch} ->
        base = main_branch(project_dir)

        case CLI.run(
               "gh",
               ["pr", "create", "--base", base, "--head", branch, "--title", title, "--fill"],
               cd: worktree_path
             ) do
          {:ok, url} -> {:ok, String.trim(url)}
          {:error, reason} -> {:error, reason}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc "Merge a PR on GitHub. Returns :ok or {:error, reason}."
  def merge_pr(project_dir, pr_url) do
    case CLI.run("gh", ["pr", "merge", pr_url, "--merge"],
           cd: project_dir,
           timeout: 60_000
         ) do
      {:ok, _} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  @doc "View PR diff. Returns {:ok, diff} or {:error, reason}."
  def pr_diff(project_dir, pr_url) do
    CLI.run("gh", ["pr", "diff", pr_url], cd: project_dir)
  end

  @doc "Get diff of a worktree branch against main. Returns {:ok, diff} or {:error, reason}."
  def worktree_diff(project_dir, worktree_path) do
    base = main_branch(project_dir)
    CLI.run("git", ["diff", "#{base}...HEAD"], cd: worktree_path)
  end

  @doc "Get PR status from GitHub. Returns {:ok, map} or {:error, reason}."
  def pr_status(project_dir, pr_url) do
    case CLI.run("gh", ["pr", "view", pr_url, "--json", "state,reviewDecision"], cd: project_dir) do
      {:ok, output} ->
        case Jason.decode(String.trim(output)) do
          {:ok, data} -> {:ok, data}
          {:error, _} -> {:error, "Failed to parse PR status JSON"}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc "Pull latest changes on the main branch."
  def pull_main(project_dir) do
    base = main_branch(project_dir)
    CLI.run("git", ["pull", "--rebase", "origin", base], cd: project_dir)
  end

  @doc "Get the recent commit log for a worktree. Returns {:ok, log} or {:error, reason}."
  def worktree_log(project_dir, worktree_path, count \\ 20) do
    base = main_branch(project_dir)
    CLI.run("git", ["log", "--oneline", "#{base}..HEAD", "-#{count}"], cd: worktree_path)
  end

  @doc "Get a compact commit log with per-commit file change stats."
  def worktree_log_with_stats(project_dir, worktree_path, count \\ 20) do
    base = main_branch(project_dir)

    CLI.run(
      "git",
      ["log", "--oneline", "--stat", "--no-color", "#{base}..HEAD", "-#{count}"],
      cd: worktree_path
    )
  end

  @doc "Get the overall diff stat (files changed, insertions, deletions) for the branch vs main."
  def worktree_diff_stat(project_dir, worktree_path) do
    base = main_branch(project_dir)
    CLI.run("git", ["diff", "--stat", "#{base}...HEAD"], cd: worktree_path)
  end

  @doc "Get a summary of uncommitted changes in a worktree."
  def worktree_status(worktree_path) do
    CLI.run("git", ["diff", "--stat", "HEAD"], cd: worktree_path)
  end

  @doc "Check if the `gh` CLI is installed and available."
  def gh_available? do
    case System.find_executable("gh") do
      nil -> false
      _path -> true
    end
  end

  @doc """
  Whether auto-PR creation is enabled. When true, the brewer automatically creates
  a GitHub PR when it finishes. When false, the user must trigger PR creation from the dashboard.
  """
  def auto_pr? do
    Application.get_env(:apothecary, :auto_pr, false)
  end

  @doc """
  Set the auto-PR flag at runtime.
  """
  def set_auto_pr(auto) when is_boolean(auto) do
    Application.put_env(:apothecary, :auto_pr, auto)
    Apothecary.Store.put_setting(:auto_pr, auto)
    :ok
  end

  @doc """
  Merge a worktree branch into main using plain git (no GitHub/PR required).

  Steps:
  1. Fetch latest main from origin
  2. Checkout main in the project dir
  3. Merge the branch (fast-forward if possible, otherwise merge commit)
  4. Push main to origin
  5. Checkout back to the original branch (if we were on one)

  Returns :ok or {:error, reason}.
  """
  def git_merge(project_dir, branch) do
    base = main_branch(project_dir)

    with {:ok, _} <- CLI.run("git", ["fetch", "origin", base], cd: project_dir),
         {:ok, original_branch} <- current_branch_or_detached(project_dir),
         {:ok, _} <- CLI.run("git", ["checkout", base], cd: project_dir),
         {:ok, _} <- CLI.run("git", ["pull", "--ff-only", "origin", base], cd: project_dir),
         {:ok, _} <- CLI.run("git", ["merge", branch, "--no-edit"], cd: project_dir),
         {:ok, _} <- CLI.run("git", ["push", "origin", base], cd: project_dir) do
      # Try to go back to the original branch (best-effort)
      if original_branch && original_branch != base do
        CLI.run("git", ["checkout", original_branch], cd: project_dir)
      end

      :ok
    else
      {:error, reason} = error ->
        # Try to recover: go back to whatever branch we were on
        CLI.run("git", ["checkout", "-"], cd: project_dir)
        Logger.warning("git_merge failed for branch #{branch}: #{inspect(reason)}")
        error
    end
  end

  @doc """
  Check if a branch has been merged into main.
  Returns true if all commits on the branch are reachable from main.
  """
  def branch_merged?(project_dir, branch) do
    base = main_branch(project_dir)

    case CLI.run("git", ["merge-base", "--is-ancestor", branch, base], cd: project_dir) do
      {:ok, _} -> true
      {:error, _} -> false
    end
  end

  @doc """
  Get the merge mode. Returns :github when GitHub PRs are used, :git for plain git merges.
  """
  def merge_mode do
    Application.get_env(:apothecary, :merge_mode, :git)
  end

  @doc "Set the merge mode at runtime (:github or :git)."
  def set_merge_mode(mode) when mode in [:github, :git] do
    Application.put_env(:apothecary, :merge_mode, mode)
    Apothecary.Store.put_setting(:merge_mode, mode)
    :ok
  end

  @doc "Delete a local branch. Uses -D (force) since the branch may already be merged."
  def delete_branch(project_dir, branch) do
    CLI.run("git", ["branch", "-D", branch], cd: project_dir)
  end

  defp current_branch_or_detached(path) do
    case current_branch(path) do
      {:ok, ""} -> {:ok, nil}
      {:ok, branch} -> {:ok, branch}
      {:error, _} -> {:ok, nil}
    end
  end

  defp parse_worktrees(output) do
    output
    |> String.split("\n\n", trim: true)
    |> Enum.map(&parse_worktree_block/1)
  end

  defp parse_worktree_block(block) do
    block
    |> String.split("\n", trim: true)
    |> Enum.reduce(%{}, fn line, acc ->
      case String.split(line, " ", parts: 2) do
        ["worktree", path] -> Map.put(acc, :path, path)
        ["HEAD", sha] -> Map.put(acc, :head, sha)
        ["branch", ref] -> Map.put(acc, :branch, ref |> String.replace("refs/heads/", ""))
        ["bare"] -> Map.put(acc, :bare, true)
        ["detached"] -> Map.put(acc, :detached, true)
        _ -> acc
      end
    end)
  end
end
