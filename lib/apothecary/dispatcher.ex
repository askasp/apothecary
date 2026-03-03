defmodule Apothecary.Dispatcher do
  @moduledoc """
  Coordinates concoction assignment between the ingredient queue and brewers.

  Concoction-centric dispatch model:
  - Each concoction gets its own git worktree and one brewer
  - Brewers work on all ingredients within their assigned concoction
  - Different concoctions can run in parallel across different brewers
  """

  use GenServer
  require Logger

  @pubsub Apothecary.PubSub
  @topic "dispatcher:updates"
  @dispatch_interval 5_000
  @max_fast_failures 3
  @backoff_ms 30_000
  @fast_failure_window_ms 60_000

  # Client API

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc "Start the swarm with N brewers."
  def start_swarm(brewer_count) do
    GenServer.call(__MODULE__, {:start_swarm, brewer_count}, 60_000)
  end

  @doc "Stop the swarm, terminating all brewers."
  def stop_swarm do
    GenServer.call(__MODULE__, :stop_swarm, 30_000)
  end

  @doc "Set the target brewer count (scale up/down)."
  def set_agent_count(count) do
    GenServer.call(__MODULE__, {:set_agent_count, count}, 60_000)
  end

  @doc "Report a brewer as idle and ready for the next concoction."
  def agent_idle(brewer_pid) do
    GenServer.cast(__MODULE__, {:agent_idle, brewer_pid})
  end

  @doc "Get dispatcher status."
  def status do
    GenServer.call(__MODULE__, :status)
  end

  @doc "Subscribe to dispatcher updates."
  def subscribe do
    Phoenix.PubSub.subscribe(@pubsub, @topic)
  end

  # Server Callbacks

  @impl true
  def init(_opts) do
    # Subscribe to ingredient updates for reactive dispatch
    Apothecary.Ingredients.subscribe()

    state = %{
      status: :paused,
      target_count: 0,
      agent_pids: [],
      idle_agents: [],
      agents: %{},
      # Track consecutive fast failures per brewer slot for backoff
      # %{slot_id => %{count: N, last_failure: monotonic_time}}
      failure_tracker: %{},
      backoff_timers: %{}
    }

    {:ok, state}
  end

  @impl true
  def handle_call({:start_swarm, count}, _from, state) do
    Logger.info("Starting swarm with #{count} brewers")
    state = %{state | status: :running, target_count: count}
    state = scale_agents(state)
    schedule_dispatch()
    broadcast(state)
    {:reply, :ok, state}
  end

  @impl true
  def handle_call(:stop_swarm, _from, state) do
    Logger.info("Stopping swarm")

    Enum.each(state.agent_pids, fn pid ->
      Apothecary.BrewerSupervisor.stop_brewer(pid)
    end)

    # Cancel any pending backoff timers
    Enum.each(state.backoff_timers, fn {_slot, timer} -> Process.cancel_timer(timer) end)

    state = %{
      state
      | status: :paused,
        target_count: 0,
        agent_pids: [],
        idle_agents: [],
        agents: %{},
        failure_tracker: %{},
        backoff_timers: %{}
    }

    broadcast(state)
    {:reply, :ok, state}
  end

  @impl true
  def handle_call({:set_agent_count, count}, _from, state) do
    state = %{state | target_count: count}
    state = scale_agents(state)
    broadcast(state)
    {:reply, :ok, state}
  end

  @impl true
  def handle_call(:status, _from, state) do
    info = %{
      status: state.status,
      target_count: state.target_count,
      active_count: length(state.agent_pids),
      idle_count: length(state.idle_agents),
      agents: state.agents
    }

    {:reply, info, state}
  end

  @impl true
  def handle_cast({:agent_idle, pid}, state) do
    idle = if pid in state.idle_agents, do: state.idle_agents, else: [pid | state.idle_agents]

    # Reset failure counter on successful idle (brewer completed work)
    brewer_state = state.agents[pid]
    slot_id = if brewer_state, do: brewer_state.id, else: :erlang.phash2(pid)
    failure_tracker = Map.delete(state.failure_tracker, slot_id)

    state = %{state | idle_agents: idle, failure_tracker: failure_tracker}
    state = try_dispatch(state)
    broadcast(state)
    {:noreply, state}
  end

  @impl true
  def handle_cast({:agent_update, pid, brewer_state}, state) do
    agents = Map.put(state.agents, pid, brewer_state)
    state = %{state | agents: agents}
    broadcast(state)
    {:noreply, state}
  end

  @impl true
  def handle_info(:dispatch, %{status: :running} = state) do
    state = try_dispatch(state)
    schedule_dispatch()
    {:noreply, state}
  end

  @impl true
  def handle_info(:dispatch, state) do
    {:noreply, state}
  end

  # React to ingredient state changes (replaces polling)
  @impl true
  def handle_info({:ingredients_update, _state}, %{status: :running} = state) do
    state = try_dispatch(state)
    {:noreply, state}
  end

  def handle_info({:ingredients_update, _state}, state) do
    {:noreply, state}
  end

  @impl true
  def handle_info({:DOWN, _ref, :process, pid, reason}, state) do
    brewer_state = state.agents[pid]
    slot_id = if brewer_state, do: brewer_state.id, else: :erlang.phash2(pid)
    Logger.warning("Brewer #{inspect(slot_id)} (#{inspect(pid)}) went down: #{inspect(reason)}")

    agent_pids = List.delete(state.agent_pids, pid)
    idle_agents = List.delete(state.idle_agents, pid)
    agents = Map.delete(state.agents, pid)
    state = %{state | agent_pids: agent_pids, idle_agents: idle_agents, agents: agents}

    # Track failure for backoff
    state = record_failure(state, slot_id)

    if should_backoff?(state, slot_id) do
      Logger.warning(
        "Brewer slot #{slot_id} hit #{@max_fast_failures} fast failures, " <>
          "backing off #{div(@backoff_ms, 1000)}s before respawn"
      )

      timer = Process.send_after(self(), {:backoff_expired, slot_id}, @backoff_ms)
      state = put_in(state.backoff_timers[slot_id], timer)
      broadcast(state)
      {:noreply, state}
    else
      state = scale_agents(state)
      broadcast(state)
      {:noreply, state}
    end
  end

  @impl true
  def handle_info({:backoff_expired, slot_id}, state) do
    Logger.info("Backoff expired for brewer slot #{slot_id}, attempting respawn")
    state = %{state | backoff_timers: Map.delete(state.backoff_timers, slot_id)}
    state = scale_agents(state)
    broadcast(state)
    {:noreply, state}
  end

  # Private

  defp schedule_dispatch do
    Process.send_after(self(), :dispatch, @dispatch_interval)
  end

  defp scale_agents(%{status: :paused} = state), do: state

  defp scale_agents(state) do
    current = length(state.agent_pids)
    target = state.target_count

    cond do
      current < target ->
        new_agents =
          for id <- (current + 1)..target do
            case Apothecary.BrewerSupervisor.start_brewer(id) do
              {:ok, pid} ->
                Process.monitor(pid)
                pid

              {:error, reason} ->
                Logger.error("Failed to start brewer #{id}: #{inspect(reason)}")
                nil
            end
          end
          |> Enum.reject(&is_nil/1)

        %{
          state
          | agent_pids: state.agent_pids ++ new_agents,
            idle_agents: state.idle_agents ++ new_agents
        }

      current > target ->
        {to_stop, to_keep} = Enum.split(state.agent_pids, current - target)
        Enum.each(to_stop, &Apothecary.BrewerSupervisor.stop_brewer/1)

        %{
          state
          | agent_pids: to_keep,
            idle_agents: state.idle_agents -- to_stop,
            agents: Map.drop(state.agents, to_stop)
        }

      true ->
        state
    end
  end

  defp try_dispatch(%{idle_agents: []} = state), do: state
  defp try_dispatch(%{status: :paused} = state), do: state

  defp try_dispatch(state) do
    case Apothecary.Ingredients.ready_concoctions() do
      [] ->
        state

      concoctions ->
        dispatch_first_available(concoctions, state)
    end
  end

  defp dispatch_first_available([], state), do: state
  defp dispatch_first_available(_concoctions, %{idle_agents: []} = state), do: state

  defp dispatch_first_available([concoction | rest], state) do
    [brewer_pid | _] = state.idle_agents
    brewer_state = state.agents[brewer_pid]
    brewer_id = if brewer_state, do: brewer_state.id, else: :erlang.phash2(brewer_pid)

    # Atomically claim the concoction
    case Apothecary.Ingredients.claim_concoction(concoction.id, brewer_id) do
      {:ok, claimed} ->
        project_dir = resolve_project_dir(concoction)

        if concoction.kind == "question" do
          # Questions run read-only against the project directory — no worktree needed
          [_ | rest_idle] = state.idle_agents
          Apothecary.Brewer.assign_concoction(brewer_pid, claimed, project_dir, nil, project_dir)
          %{state | idle_agents: rest_idle}
        else
          # Task concoctions get their own git worktree
          case ensure_git_worktree(concoction, project_dir) do
            {:ok, path, branch} ->
              Apothecary.Ingredients.update_concoction(concoction.id, %{
                git_path: path,
                git_branch: branch
              })

              [_ | rest_idle] = state.idle_agents
              Apothecary.Brewer.assign_concoction(brewer_pid, claimed, path, branch, project_dir)
              %{state | idle_agents: rest_idle}

            {:error, reason} ->
              Logger.error(
                "Failed to create git worktree for #{concoction.id}: #{inspect(reason)}"
              )

              Apothecary.Ingredients.release_concoction(concoction.id)
              dispatch_first_available(rest, state)
          end
        end

      {:error, _} ->
        dispatch_first_available(rest, state)
    end
  end

  defp ensure_git_worktree(%{git_path: path, git_branch: branch}, project_dir)
       when not is_nil(path) and not is_nil(branch) do
    if File.dir?(path) do
      {:ok, path, branch}
    else
      # Git worktree was removed, recreate
      Apothecary.WorktreeManager.checkout(project_dir, path)
    end
  end

  defp ensure_git_worktree(concoction, project_dir) do
    Apothecary.WorktreeManager.checkout(project_dir, concoction.id)
  end

  defp resolve_project_dir(%{project_id: project_id}) when not is_nil(project_id) do
    case Apothecary.Projects.get(project_id) do
      {:ok, project} -> project.path
      _ -> nil
    end
  end

  defp resolve_project_dir(_), do: nil

  defp record_failure(state, slot_id) do
    now = System.monotonic_time(:millisecond)

    entry =
      case state.failure_tracker[slot_id] do
        %{count: count, first_failure: first} ->
          if now - first > @fast_failure_window_ms do
            # Window expired, start fresh
            %{count: 1, first_failure: now}
          else
            %{count: count + 1, first_failure: first}
          end

        nil ->
          %{count: 1, first_failure: now}
      end

    %{state | failure_tracker: Map.put(state.failure_tracker, slot_id, entry)}
  end

  defp should_backoff?(state, slot_id) do
    case state.failure_tracker[slot_id] do
      %{count: count} when count >= @max_fast_failures -> true
      _ -> false
    end
  end

  defp broadcast(state) do
    Phoenix.PubSub.broadcast(@pubsub, @topic, {:dispatcher_update, status_map(state)})
  end

  defp status_map(state) do
    %{
      status: state.status,
      target_count: state.target_count,
      active_count: length(state.agent_pids),
      idle_count: length(state.idle_agents),
      agents: state.agents
    }
  end
end
