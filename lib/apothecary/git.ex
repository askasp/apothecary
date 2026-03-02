defmodule Apothecary.Git do
  @moduledoc "Git CLI wrapper for worktree and repository inspection."

  alias Apothecary.CLI

  defp project_dir, do: Application.get_env(:apothecary, :project_dir)

  @doc "List all git worktrees in porcelain format."
  def list_worktrees do
    case CLI.run("git", ["worktree", "list", "--porcelain"], cd: project_dir()) do
      {:ok, output} -> {:ok, parse_worktrees(output)}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc "Create a new worktree with a branch based on the given base branch."
  def create_worktree(path, branch, base_branch \\ "main") do
    CLI.run("git", ["worktree", "add", "-b", branch, path, base_branch], cd: project_dir())
  end

  @doc "Remove a worktree."
  def remove_worktree(path) do
    CLI.run("git", ["worktree", "remove", "--force", path], cd: project_dir())
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
  def main_branch do
    dir = project_dir()

    case CLI.run("git", ["symbolic-ref", "refs/remotes/origin/HEAD", "--short"], cd: dir) do
      {:ok, ref} ->
        ref |> String.trim() |> String.split("/") |> List.last()

      {:error, _} ->
        # Fallback: check if main or master exists
        case CLI.run("git", ["rev-parse", "--verify", "main"], cd: dir) do
          {:ok, _} -> "main"
          _ -> "master"
        end
    end
  end

  @doc "Reset a worktree branch to the latest main."
  def reset_to_main(worktree_path) do
    base = main_branch()

    with {:ok, _} <- CLI.run("git", ["fetch", "origin", base], cd: worktree_path),
         {:ok, _} <- CLI.run("git", ["reset", "--hard", "origin/#{base}"], cd: worktree_path) do
      :ok
    end
  end

  @doc "Fetch latest main and merge it into the current worktree branch."
  def merge_main_into(worktree_path) do
    base = main_branch()

    with {:ok, _} <- CLI.run("git", ["fetch", "origin", base], cd: worktree_path),
         {:ok, _} <- CLI.run("git", ["merge", "origin/#{base}", "--no-edit"], cd: worktree_path) do
      :ok
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
  def create_pr(worktree_path, title) do
    case current_branch(worktree_path) do
      {:ok, branch} ->
        base = main_branch()

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
  def merge_pr(pr_url) do
    # Don't use --delete-branch: the branch is checked out in a worktree,
    # so local branch deletion fails and causes gh to report an error even
    # though the merge succeeded. We handle cleanup via WorktreeManager.release.
    case CLI.run("gh", ["pr", "merge", pr_url, "--merge"],
           cd: project_dir(),
           timeout: 60_000
         ) do
      {:ok, _} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  @doc "View PR diff. Returns {:ok, diff} or {:error, reason}."
  def pr_diff(pr_url) do
    CLI.run("gh", ["pr", "diff", pr_url], cd: project_dir())
  end

  @doc "Get diff of a worktree branch against main. Returns {:ok, diff} or {:error, reason}."
  def worktree_diff(worktree_path) do
    base = main_branch()
    CLI.run("git", ["diff", "#{base}...HEAD"], cd: worktree_path)
  end

  @doc "Get PR status from GitHub. Returns {:ok, map} or {:error, reason}."
  def pr_status(pr_url) do
    case CLI.run("gh", ["pr", "view", pr_url, "--json", "state,reviewDecision"],
           cd: project_dir()
         ) do
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
  def pull_main do
    base = main_branch()
    CLI.run("git", ["pull", "--rebase", "origin", base], cd: project_dir())
  end

  @doc "Get the recent commit log for a worktree. Returns {:ok, log} or {:error, reason}."
  def worktree_log(worktree_path, count \\ 20) do
    base = main_branch()

    CLI.run("git", ["log", "--oneline", "#{base}..HEAD", "-#{count}"], cd: worktree_path)
  end

  @doc "Get a summary of uncommitted changes in a worktree. Returns {:ok, diff_stat} or {:error, reason}."
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
  Get the configured merge mode setting: :auto, :github, or :local.
  """
  def merge_mode_setting do
    Application.get_env(:apothecary, :merge_mode, :auto)
  end

  @doc """
  Get the effective merge mode: :github or :local.
  When set to :auto, detects based on `gh` CLI availability.
  """
  def merge_mode do
    case merge_mode_setting() do
      :github -> :github
      :local -> :local
      :auto -> if gh_available?(), do: :github, else: :local
    end
  end

  @doc """
  Set the merge mode at runtime. Accepts :auto, :github, or :local.
  """
  def set_merge_mode(mode) when mode in [:auto, :github, :local] do
    Application.put_env(:apothecary, :merge_mode, mode)
    :ok
  end

  @doc "Merge a worktree branch into main locally. Does NOT delete the branch — cleanup happens via WorktreeManager.release."
  def local_merge(worktree_path) do
    base = main_branch()

    with {:ok, branch} <- current_branch(worktree_path),
         {:ok, _} <- CLI.run("git", ["checkout", base], cd: project_dir()),
         {:ok, _} <- CLI.run("git", ["merge", branch, "--no-edit"], cd: project_dir()) do
      :ok
    else
      {:error, reason} ->
        # Try to go back to the base branch if merge fails
        CLI.run("git", ["checkout", base], cd: project_dir())
        {:error, reason}
    end
  end

  @doc "Delete a local branch. Uses -D (force) since the branch may already be merged."
  def delete_branch(branch) do
    CLI.run("git", ["branch", "-D", branch], cd: project_dir())
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
