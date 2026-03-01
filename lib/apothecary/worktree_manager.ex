defmodule Apothecary.WorktreeManager do
  @moduledoc """
  Manages git worktrees for agent workers.

  Creates worktrees under <project_dir>-worktrees/ and tracks
  which ones are available vs checked out by agents.
  """

  use GenServer
  require Logger

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc "Check out a worktree for an agent. Returns {:ok, path, branch} or {:error, reason}."
  def checkout(agent_id) do
    GenServer.call(__MODULE__, {:checkout, agent_id}, 30_000)
  end

  @doc "Release a worktree back to the pool."
  def release(agent_id) do
    GenServer.cast(__MODULE__, {:release, agent_id})
  end

  @doc "Get the worktrees base directory."
  def worktrees_dir do
    project_dir = Application.get_env(:apothecary, :project_dir)
    "#{project_dir}-worktrees"
  end

  # Server

  @impl true
  def init(_opts) do
    state = %{
      checked_out: %{}
    }

    {:ok, state}
  end

  @impl true
  def handle_call({:checkout, agent_id}, _from, state) do
    project_dir = Application.get_env(:apothecary, :project_dir)

    if project_dir do
      base_dir = worktrees_dir()
      File.mkdir_p!(base_dir)

      branch = "agent-#{agent_id}-#{System.system_time(:second)}"
      path = Path.join(base_dir, "agent-#{agent_id}")

      # Remove existing worktree if present
      if File.dir?(path) do
        Apothecary.Git.remove_worktree(path)
      end

      base_branch = Apothecary.Git.main_branch()

      case Apothecary.Git.create_worktree(path, branch, base_branch) do
        {:ok, _} ->
          state = put_in(state, [:checked_out, agent_id], %{path: path, branch: branch})
          {:reply, {:ok, path, branch}, state}

        {:error, reason} ->
          {:reply, {:error, reason}, state}
      end
    else
      {:reply, {:error, "no project_dir configured"}, state}
    end
  end

  @impl true
  def handle_cast({:release, agent_id}, state) do
    case Map.pop(state.checked_out, agent_id) do
      {nil, _state} ->
        {:noreply, state}

      {_worktree, new_checked_out} ->
        {:noreply, %{state | checked_out: new_checked_out}}
    end
  end
end
