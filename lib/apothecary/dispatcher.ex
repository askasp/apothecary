defmodule Apothecary.Dispatcher do
  @moduledoc """
  Coordinates task assignment between the beads queue and agent workers.

  Starts in :paused state. The user starts the swarm from the UI, which
  transitions to :running and begins claiming tasks for idle agents.
  """

  use GenServer
  require Logger

  @pubsub Apothecary.PubSub
  @topic "dispatcher:updates"
  @dispatch_interval 3_000

  # Client API

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc "Start the swarm with N agents."
  def start_swarm(agent_count) do
    GenServer.call(__MODULE__, {:start_swarm, agent_count}, 60_000)
  end

  @doc "Stop the swarm, terminating all agents."
  def stop_swarm do
    GenServer.call(__MODULE__, :stop_swarm, 30_000)
  end

  @doc "Set the target agent count (scale up/down)."
  def set_agent_count(count) do
    GenServer.call(__MODULE__, {:set_agent_count, count}, 60_000)
  end

  @doc "Report an agent as idle and ready for the next task."
  def agent_idle(agent_pid) do
    GenServer.cast(__MODULE__, {:agent_idle, agent_pid})
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
    state = %{
      status: :paused,
      target_count: 0,
      agent_pids: [],
      idle_agents: [],
      agents: %{}
    }

    {:ok, state}
  end

  @impl true
  def handle_call({:start_swarm, count}, _from, state) do
    Logger.info("Starting swarm with #{count} agents")
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
      Apothecary.AgentSupervisor.stop_agent(pid)
    end)

    state = %{
      state
      | status: :paused,
        target_count: 0,
        agent_pids: [],
        idle_agents: [],
        agents: %{}
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
    state = %{state | idle_agents: idle}
    state = try_dispatch(state)
    broadcast(state)
    {:noreply, state}
  end

  @impl true
  def handle_cast({:agent_update, pid, agent_state}, state) do
    agents = Map.put(state.agents, pid, agent_state)
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

  @impl true
  def handle_info({:DOWN, _ref, :process, pid, _reason}, state) do
    Logger.warning("Agent #{inspect(pid)} went down")
    agent_pids = List.delete(state.agent_pids, pid)
    idle_agents = List.delete(state.idle_agents, pid)
    agents = Map.delete(state.agents, pid)
    state = %{state | agent_pids: agent_pids, idle_agents: idle_agents, agents: agents}
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
            case Apothecary.AgentSupervisor.start_agent(id) do
              {:ok, pid} ->
                Process.monitor(pid)
                pid

              {:error, reason} ->
                Logger.error("Failed to start agent #{id}: #{inspect(reason)}")
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
        Enum.each(to_stop, &Apothecary.AgentSupervisor.stop_agent/1)

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
    case Apothecary.Beads.ready() do
      {:ok, [task | _]} ->
        case Apothecary.Beads.claim(task.id) do
          {:ok, _} ->
            [agent_pid | rest] = state.idle_agents
            Apothecary.AgentWorker.assign_task(agent_pid, task)
            %{state | idle_agents: rest}

          {:error, _} ->
            state
        end

      _ ->
        state
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
