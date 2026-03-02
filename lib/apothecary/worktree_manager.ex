defmodule Apothecary.WorktreeManager do
  @moduledoc """
  Manages git worktrees for work units.

  Creates one worktree per work unit under <project_dir>-worktrees/<id>/
  with a stable branch name `worktree/<id>`. Supports dependency chains
  where a child worktree branches from its parent's branch.
  """

  use GenServer
  require Logger

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Check out a worktree. Returns {:ok, path, branch} or {:error, reason}.

  Options:
  - parent_worktree_id: branch from parent's branch instead of main
  """
  def checkout(worktree_id, opts \\ []) do
    GenServer.call(__MODULE__, {:checkout, worktree_id, opts}, 30_000)
  end

  @doc "Look up an existing worktree. Returns {:ok, path, branch} or :not_found."
  def get_worktree(worktree_id) do
    GenServer.call(__MODULE__, {:get_worktree, worktree_id})
  end

  @doc "Release a worktree (removes it from disk). Only call after work is fully done."
  def release(worktree_id) do
    GenServer.cast(__MODULE__, {:release, worktree_id})
  end

  @doc "Get the worktrees base directory."
  def worktrees_dir do
    project_dir = Application.get_env(:apothecary, :project_dir)
    "#{project_dir}-worktrees"
  end

  # Server

  @impl true
  def init(_opts) do
    worktrees = recover_state_from_disk()
    Logger.info("WorktreeManager initialized with #{map_size(worktrees)} worktree(s) from disk")
    {:ok, %{worktrees: worktrees}}
  end

  @impl true
  def handle_call({:checkout, worktree_id, opts}, _from, state) do
    worktree_id = to_string(worktree_id)

    # If we already have a worktree for this ID, return it
    case Map.get(state.worktrees, worktree_id) do
      %{path: path, branch: branch} ->
        {:reply, {:ok, path, branch}, state}

      nil ->
        parent_worktree_id = opts[:parent_worktree_id]

        # Determine base branch
        base_branch =
          if parent_worktree_id do
            case Map.get(state.worktrees, to_string(parent_worktree_id)) do
              %{branch: parent_branch} -> parent_branch
              nil -> Apothecary.Git.main_branch()
            end
          else
            Apothecary.Git.main_branch()
          end

        case create_worktree(worktree_id, base_branch) do
          {:ok, path, branch} ->
            entry = %{path: path, branch: branch, parent_worktree_id: parent_worktree_id}
            worktrees = Map.put(state.worktrees, worktree_id, entry)
            {:reply, {:ok, path, branch}, %{state | worktrees: worktrees}}

          {:error, reason} ->
            {:reply, {:error, reason}, state}
        end
    end
  end

  @impl true
  def handle_call({:get_worktree, worktree_id}, _from, state) do
    worktree_id = to_string(worktree_id)

    case Map.get(state.worktrees, worktree_id) do
      %{path: path, branch: branch} -> {:reply, {:ok, path, branch}, state}
      nil -> {:reply, :not_found, state}
    end
  end

  @impl true
  def handle_cast({:release, worktree_id}, state) do
    worktree_id = to_string(worktree_id)

    case Map.pop(state.worktrees, worktree_id) do
      {nil, _} ->
        {:noreply, state}

      {%{path: path}, new_worktrees} ->
        Logger.info("Releasing worktree for #{worktree_id}: #{path}")

        case Apothecary.Git.remove_worktree(path) do
          {:ok, _} ->
            Logger.info("Successfully removed worktree #{worktree_id} at #{path}")

          {:error, reason} ->
            Logger.warning(
              "Failed to remove worktree #{worktree_id} at #{path}: #{inspect(reason)}. " <>
                "You may need to manually run: git worktree remove --force #{path}"
            )
        end

        # Remove from state regardless — the worktree is logically released
        {:noreply, %{state | worktrees: new_worktrees}}
    end
  end

  defp recover_state_from_disk do
    base_dir = worktrees_dir()

    if File.dir?(base_dir) do
      case File.ls(base_dir) do
        {:ok, entries} ->
          entries
          |> Enum.filter(fn entry -> File.dir?(Path.join(base_dir, entry)) end)
          |> Enum.reduce(%{}, fn dir_name, acc ->
            path = Path.join(base_dir, dir_name)

            case Apothecary.Git.current_branch(path) do
              {:ok, branch} ->
                # Reconstruct worktree_id from directory name
                worktree_id = dir_name
                entry = %{path: path, branch: branch, parent_worktree_id: nil}
                Logger.info("Recovered worktree #{worktree_id}: #{path} (branch: #{branch})")
                Map.put(acc, worktree_id, entry)

              {:error, _} ->
                Logger.warning("Skipping non-git directory in worktrees: #{path}")
                acc
            end
          end)

        {:error, reason} ->
          Logger.warning("Failed to list worktrees dir #{base_dir}: #{inspect(reason)}")
          %{}
      end
    else
      %{}
    end
  end

  defp create_worktree(worktree_id, base_branch) do
    project_dir = Application.get_env(:apothecary, :project_dir)

    if project_dir do
      base_dir = worktrees_dir()
      File.mkdir_p!(base_dir)

      # Sanitize worktree_id for use in path/branch (replace non-alphanum with dash)
      safe_id = String.replace(worktree_id, ~r/[^a-zA-Z0-9_-]/, "-")
      branch = "worktree/#{safe_id}"
      path = Path.join(base_dir, safe_id)

      # Remove existing worktree if present (stale from previous run)
      if File.dir?(path) do
        Apothecary.Git.remove_worktree(path)
      end

      # Fetch latest main so the worktree branches from up-to-date code
      case Apothecary.Git.pull_main() do
        {:ok, _} ->
          :ok

        {:error, reason} ->
          Logger.warning(
            "Failed to pull main before creating worktree #{worktree_id}: #{inspect(reason)}"
          )
      end

      case Apothecary.Git.create_worktree(path, branch, base_branch) do
        {:ok, _} ->
          Logger.info("Created worktree for #{worktree_id}: #{path} (branch: #{branch})")
          {:ok, path, branch}

        {:error, reason} ->
          {:error, reason}
      end
    else
      {:error, "no project_dir configured"}
    end
  end
end
