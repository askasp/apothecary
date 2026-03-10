defmodule Apothecary.WorktreeManager do
  @moduledoc """
  Manages git worktrees for work units across multiple projects.

  Creates one worktree per work unit under ~/.apothecary/worktrees/<project-hash>/<id>/
  with a stable branch name `worktree/<id>`. Supports dependency chains
  where a child worktree branches from its parent's branch.

  Each checkout call specifies the project_dir, allowing worktrees
  for different projects to coexist without conflicts.
  """

  use GenServer
  require Logger

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Check out a worktree for a project. Returns {:ok, path, branch} or {:error, reason}.

  Options:
  - parent_worktree_id: branch from parent's branch instead of main
  """
  def checkout(project_dir, worktree_id, opts \\ []) do
    GenServer.call(__MODULE__, {:checkout, project_dir, worktree_id, opts}, 30_000)
  end

  @doc "Look up an existing worktree. Returns {:ok, path, branch} or :not_found."
  def get_worktree(worktree_id) do
    GenServer.call(__MODULE__, {:get_worktree, worktree_id})
  end

  @doc "Look up full worktree info including project_dir. Returns {:ok, info_map} or :not_found."
  def get_worktree_info(worktree_id) do
    GenServer.call(__MODULE__, {:get_worktree_info, worktree_id})
  end

  @doc "Release a worktree (removes it from disk). Only call after work is fully done."
  def release(worktree_id) do
    GenServer.cast(__MODULE__, {:release, worktree_id})
  end

  @doc "List worktree directories on disk for a project. Returns list of {id, path} tuples."
  def list_on_disk(project_dir) do
    base = worktrees_dir(project_dir)

    if File.dir?(base) do
      case File.ls(base) do
        {:ok, entries} ->
          entries
          |> Enum.filter(fn entry -> File.dir?(Path.join(base, entry)) end)
          |> Enum.sort()
          |> Enum.map(fn dir_name -> {dir_name, Path.join(base, dir_name)} end)

        _ ->
          []
      end
    else
      []
    end
  end

  @doc "Get the worktrees base directory for a project."
  def worktrees_dir(project_dir) do
    # Use a short hash of the expanded path to avoid collisions between
    # projects with the same directory name in different locations.
    expanded = Path.expand(project_dir)
    hash = :crypto.hash(:sha256, expanded) |> Base.encode16(case: :lower) |> binary_part(0, 8)
    dir_name = "#{Path.basename(expanded)}-#{hash}"

    Path.join([System.user_home!(), ".apothecary", "worktrees", dir_name])
  end

  # Server

  @impl true
  def init(_opts) do
    worktrees = recover_state_from_disk()
    Logger.info("WorktreeManager initialized with #{map_size(worktrees)} worktree(s) from disk")
    {:ok, %{worktrees: worktrees}}
  end

  @impl true
  def handle_call({:checkout, project_dir, worktree_id, opts}, _from, state) do
    worktree_id = to_string(worktree_id)

    case Map.get(state.worktrees, worktree_id) do
      %{path: path, branch: branch} ->
        {:reply, {:ok, path, branch}, state}

      nil ->
        parent_worktree_id = opts[:parent_worktree_id]

        base_branch =
          if parent_worktree_id do
            case Map.get(state.worktrees, to_string(parent_worktree_id)) do
              %{branch: parent_branch} -> parent_branch
              nil -> Apothecary.Git.main_branch(project_dir)
            end
          else
            Apothecary.Git.main_branch(project_dir)
          end

        case create_worktree(project_dir, worktree_id, base_branch, opts) do
          {:ok, path, branch} ->
            entry = %{
              path: path,
              branch: branch,
              parent_worktree_id: parent_worktree_id,
              project_dir: project_dir
            }

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
  def handle_call({:get_worktree_info, worktree_id}, _from, state) do
    worktree_id = to_string(worktree_id)

    case Map.get(state.worktrees, worktree_id) do
      %{} = info -> {:reply, {:ok, info}, state}
      nil -> {:reply, :not_found, state}
    end
  end

  @impl true
  def handle_cast({:release, worktree_id}, state) do
    worktree_id = to_string(worktree_id)

    case Map.pop(state.worktrees, worktree_id) do
      {nil, _} ->
        {:noreply, state}

      {%{path: path, branch: branch, project_dir: proj_dir}, new_worktrees} ->
        Logger.info("Releasing worktree for #{worktree_id}: #{path}")

        case Apothecary.Git.remove_worktree(proj_dir, path) do
          {:ok, _} ->
            Logger.info("Successfully removed worktree #{worktree_id} at #{path}")

          {:error, reason} ->
            Logger.warning(
              "Failed to remove worktree #{worktree_id} at #{path}: #{inspect(reason)}. " <>
                "You may need to manually run: git worktree remove --force #{path}"
            )
        end

        if branch do
          case Apothecary.Git.delete_branch(proj_dir, branch) do
            {:ok, _} ->
              Logger.info("Deleted branch #{branch} for worktree #{worktree_id}")

            {:error, reason} ->
              Logger.warning(
                "Failed to delete branch #{branch} for #{worktree_id}: #{inspect(reason)}"
              )
          end
        end

        {:noreply, %{state | worktrees: new_worktrees}}
    end
  end

  defp recover_state_from_disk do
    # Recover worktrees from all known projects
    projects =
      try do
        Apothecary.Projects.list_active()
      rescue
        _ -> []
      catch
        :exit, _ -> []
      end

    Enum.reduce(projects, %{}, fn project, acc ->
      # Check new location (~/.apothecary/worktrees/)
      acc = recover_worktrees_from_dir(worktrees_dir(project.path), project.path, acc)
      # Check legacy location (<project_dir>-worktrees/) for backwards compat
      legacy_dir = "#{project.path}-worktrees"
      recover_worktrees_from_dir(legacy_dir, project.path, acc)
    end)
  end

  defp recover_worktrees_from_dir(base_dir, project_dir, acc) do
    if File.dir?(base_dir) do
      case File.ls(base_dir) do
        {:ok, entries} ->
          entries
          |> Enum.filter(fn entry -> File.dir?(Path.join(base_dir, entry)) end)
          |> Enum.reduce(acc, fn dir_name, acc ->
            path = Path.join(base_dir, dir_name)

            case Apothecary.Git.current_branch(path) do
              {:ok, branch} ->
                worktree_id = dir_name

                entry = %{
                  path: path,
                  branch: branch,
                  parent_worktree_id: nil,
                  project_dir: project_dir
                }

                Logger.info("Recovered worktree #{worktree_id}: #{path} (branch: #{branch})")
                Map.put(acc, worktree_id, entry)

              {:error, _} ->
                Logger.warning("Skipping non-git directory in worktrees: #{path}")
                acc
            end
          end)

        {:error, reason} ->
          Logger.warning("Failed to list worktrees dir #{base_dir}: #{inspect(reason)}")
          acc
      end
    else
      acc
    end
  end

  defp create_worktree(project_dir, worktree_id, base_branch, opts) do
    base_dir = worktrees_dir(project_dir)
    File.mkdir_p!(base_dir)

    safe_id = String.replace(worktree_id, ~r/[^a-zA-Z0-9_-]/, "-")
    branch = branch_name_from_id(worktree_id, opts[:title])
    path = Path.join(base_dir, safe_id)

    if File.dir?(path) do
      Apothecary.Git.remove_worktree(project_dir, path)
    end

    case Apothecary.Git.pull_main(project_dir) do
      {:ok, _} ->
        :ok

      {:error, reason} ->
        Logger.warning(
          "Failed to pull main before creating worktree #{worktree_id}: #{inspect(reason)}"
        )
    end

    case Apothecary.Git.create_worktree(project_dir, path, branch, base_branch) do
      {:ok, _} ->
        Logger.info("Created worktree for #{worktree_id}: #{path} (branch: #{branch})")
        {:ok, path, branch}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp branch_name_from_id(worktree_id, nil) do
    safe_id = String.replace(worktree_id, ~r/[^a-zA-Z0-9_-]/, "-")
    "worktree/#{safe_id}"
  end

  defp branch_name_from_id(worktree_id, title) do
    slug =
      title
      |> String.downcase()
      |> String.replace(~r/[^a-z0-9\s\/._-]/, "")
      |> String.trim()
      |> String.replace(~r/\s+/, "-")
      |> String.slice(0, 60)
      |> String.trim_trailing("-")

    if slug == "" do
      branch_name_from_id(worktree_id, nil)
    else
      # Append short suffix from worktree ID to avoid branch name collisions
      suffix = worktree_id |> String.replace("wt-", "") |> String.slice(0, 4)
      "#{slug}-#{suffix}"
    end
  end
end
