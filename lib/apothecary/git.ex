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

  @doc "Pull latest changes on the main branch."
  def pull_main do
    base = main_branch()
    CLI.run("git", ["pull", "--rebase", "origin", base], cd: project_dir())
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
