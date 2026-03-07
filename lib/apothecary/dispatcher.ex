defmodule Apothecary.Dispatcher do
  @moduledoc """
  Coordinates worktree assignment between the task queue and brewers.

  Per-project dispatch model:
  - Each project has its own pool of brewers
  - Brewers are scoped to a single project and only pick up that project's worktrees
  - You can start/stop brewing independently per project
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

  @doc "Start the swarm for a specific project with N brewers."
  def start_swarm(project_id, brewer_count) do
    GenServer.call(__MODULE__, {:start_swarm, project_id, brewer_count}, 60_000)
  end

  @doc "Stop the swarm for a specific project, terminating its brewers."
  def stop_swarm(project_id) do
    GenServer.call(__MODULE__, {:stop_swarm, project_id}, 30_000)
  end

  @doc "Set the target brewer count for a specific project (scale up/down)."
  def set_agent_count(project_id, count) do
    GenServer.call(__MODULE__, {:set_agent_count, project_id, count}, 60_000)
  end

  @doc "Dispatch a question immediately with a one-off brewer (doesn't count towards pool)."
  def dispatch_question(project_id, question_worktree_id) do
    GenServer.call(__MODULE__, {:dispatch_question, project_id, question_worktree_id}, 60_000)
  end

  @doc "Report a brewer as idle and ready for the next worktree."
  def agent_idle(brewer_pid) do
    GenServer.cast(__MODULE__, {:agent_idle, brewer_pid})
  end

  @doc "Get dispatcher status for all projects."
  def status do
    GenServer.call(__MODULE__, :status)
  end

  @doc "Get dispatcher status for a specific project."
  def project_status(project_id) do
    GenServer.call(__MODULE__, {:project_status, project_id})
  end

  @doc "Subscribe to dispatcher updates."
  def subscribe do
    Phoenix.PubSub.subscribe(@pubsub, @topic)
  end

  # Server Callbacks

  @impl true
  def init(_opts) do
    # Subscribe to worktree updates for reactive dispatch
    Apothecary.Worktrees.subscribe()

    state = %{
      # Global brewer ID counter
      next_brewer_id: 1,
      # Per-project pools: %{project_id => pool}
      projects: %{},
      # Reverse lookup: pid → project_id
      brewer_projects: %{},
      # One-off question brewer pids (auto-stop when idle)
      question_pids: MapSet.new(),
      # Whether periodic dispatch is scheduled
      dispatch_scheduled: false
    }

    {:ok, state}
  end

  @impl true
  def handle_call({:start_swarm, project_id, count}, _from, state) do
    Logger.info("Starting swarm for project #{project_id} with #{count} brewers")

    pool = get_or_create_pool(state, project_id)
    pool = %{pool | status: :running, target_count: count}
    state = put_pool(state, project_id, pool)
    state = scale_project_agents(state, project_id)

    ensure_dispatch_scheduled(state)
    broadcast(state)
    {:reply, :ok, state}
  end

  @impl true
  def handle_call({:stop_swarm, project_id}, _from, state) do
    Logger.info("Stopping swarm for project #{project_id}")

    case state.projects[project_id] do
      nil ->
        {:reply, :ok, state}

      pool ->
        Enum.each(pool.agent_pids, fn pid ->
          Apothecary.BrewerSupervisor.stop_brewer(pid)
        end)

        # Cancel any pending backoff timers
        Enum.each(pool.backoff_timers, fn {_slot, timer} -> Process.cancel_timer(timer) end)

        brewer_projects = Map.drop(state.brewer_projects, pool.agent_pids)

        pool = %{pool |
          status: :paused,
          target_count: 0,
          agent_pids: [],
          idle_agents: [],
          agents: Map.drop(pool.agents, pool.agent_pids),
          failure_tracker: %{},
          backoff_timers: %{}
        }
        state = %{state | brewer_projects: brewer_projects}
        state = put_pool(state, project_id, pool)

        broadcast(state)
        {:reply, :ok, state}
    end
  end

  @impl true
  def handle_call({:set_agent_count, project_id, count}, _from, state) do
    pool = get_or_create_pool(state, project_id)
    pool = %{pool | target_count: count}
    state = put_pool(state, project_id, pool)
    state = scale_project_agents(state, project_id)
    broadcast(state)
    {:reply, :ok, state}
  end

  @impl true
  def handle_call({:dispatch_question, project_id, question_wt_id}, _from, state) do
    Logger.info("Dispatching question #{question_wt_id} for project #{project_id}")

    case Apothecary.Worktrees.get_worktree(question_wt_id) do
      {:ok, worktree} ->
        # Spawn a one-off brewer
        {pids, next_id} = start_n_brewers(state.next_brewer_id, 1)

        case pids do
          [pid] ->
            # Track it as a question brewer (auto-stop when idle)
            pool = get_or_create_pool(state, project_id)
            agents = Map.put(pool.agents, pid, %{id: next_id - 1, status: :working})
            pool = %{pool | agents: agents}

            state = %{
              state
              | next_brewer_id: next_id,
                brewer_projects: Map.put(state.brewer_projects, pid, project_id),
                question_pids: MapSet.put(state.question_pids, pid),
                projects: Map.put(state.projects, project_id, pool)
            }

            # Claim and assign immediately
            brewer_id = next_id - 1

            case Apothecary.Worktrees.claim_worktree(worktree.id, brewer_id) do
              {:ok, claimed} ->
                project_dir = resolve_project_dir(worktree)

                Apothecary.Brewer.assign_worktree(
                  pid,
                  claimed,
                  project_dir,
                  nil,
                  project_dir
                )

                broadcast(state)
                {:reply, :ok, state}

              {:error, reason} ->
                Logger.error("Failed to claim question #{question_wt_id}: #{inspect(reason)}")
                Apothecary.BrewerSupervisor.stop_brewer(pid)
                state = %{state | question_pids: MapSet.delete(state.question_pids, pid)}
                {:reply, {:error, reason}, state}
            end

          [] ->
            {:reply, {:error, :brewer_start_failed}, state}
        end

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_call(:status, _from, state) do
    info = build_global_status(state)
    {:reply, info, state}
  end

  @impl true
  def handle_call({:project_status, project_id}, _from, state) do
    info = build_project_status(state, project_id)
    {:reply, info, state}
  end

  @impl true
  def handle_cast({:agent_idle, pid}, state) do
    # One-off question brewers: auto-stop when idle
    if MapSet.member?(state.question_pids, pid) do
      Logger.info("Question brewer #{inspect(pid)} finished, stopping")
      Apothecary.BrewerSupervisor.stop_brewer(pid)
      project_id = state.brewer_projects[pid]
      pool = state.projects[project_id]

      pool =
        if pool do
          %{pool | agents: Map.delete(pool.agents, pid)}
        else
          pool
        end

      state = %{
        state
        | question_pids: MapSet.delete(state.question_pids, pid),
          brewer_projects: Map.delete(state.brewer_projects, pid)
      }

      state = if pool, do: put_pool(state, project_id, pool), else: state

      broadcast(state)
      {:noreply, state}
    else
    project_id = state.brewer_projects[pid]

    state =
      if project_id do
        pool = state.projects[project_id]

        if pool do
          idle =
            if pid in pool.idle_agents, do: pool.idle_agents, else: [pid | pool.idle_agents]
          pool = %{pool | idle_agents: idle}

          # Reset failure counter on successful idle (brewer completed work)
          brewer_state = pool.agents[pid]
          slot_id = if brewer_state, do: brewer_state.id, else: :erlang.phash2(pid)
          failure_tracker = Map.delete(pool.failure_tracker, slot_id)

          pool = %{pool | failure_tracker: failure_tracker}
          state = put_pool(state, project_id, pool)
          try_dispatch(state)
        else
          state
        end
      else
        # Brewer not associated with any project — shouldn't happen but handle gracefully
        Logger.warning("Brewer #{inspect(pid)} reported idle but has no project association")
        state
      end

    broadcast(state)
    {:noreply, state}
    end
  end

  @impl true
  def handle_cast({:agent_update, pid, brewer_state}, state) do
    project_id = state.brewer_projects[pid]

    state =
      if project_id do
        pool = state.projects[project_id]

        if pool do
          agents = Map.put(pool.agents, pid, brewer_state)
          put_pool(state, project_id, %{pool | agents: agents})
        else
          state
        end
      else
        state
      end

    broadcast(state)
    {:noreply, state}
  end

  @impl true
  def handle_info(:dispatch, state) do
    state = try_dispatch(state)
    state = maybe_schedule_dispatch(state)
    {:noreply, state}
  end

  # React to worktree state changes (replaces polling)
  @impl true
  def handle_info({:worktrees_update, _worktrees_state}, state) do
    state = try_dispatch(state)
    {:noreply, state}
  end

  @impl true
  def handle_info({:DOWN, _ref, :process, pid, reason}, state) do
    project_id = state.brewer_projects[pid]

    state =
      if project_id do
        pool = state.projects[project_id]

        if pool do
          brewer_state = pool.agents[pid]
          slot_id = if brewer_state, do: brewer_state.id, else: :erlang.phash2(pid)

          Logger.warning(
            "Brewer #{inspect(slot_id)} (#{inspect(pid)}) in project #{project_id} went down: #{inspect(reason)}"
          )

          is_question = MapSet.member?(state.question_pids, pid)

          pool = %{pool |
            agent_pids: List.delete(pool.agent_pids, pid),
            idle_agents: List.delete(pool.idle_agents, pid),
            agents: Map.delete(pool.agents, pid)
          }

          state = %{state | question_pids: MapSet.delete(state.question_pids, pid)}

          # Question brewers don't need failure tracking / respawn
          if is_question do
            brewer_projects = Map.delete(state.brewer_projects, pid)
            state = %{state | brewer_projects: brewer_projects}
            put_pool(state, project_id, pool)
          else

          pool = record_pool_failure(pool, slot_id)

          brewer_projects = Map.delete(state.brewer_projects, pid)
          state = %{state | brewer_projects: brewer_projects}

          if should_pool_backoff?(pool, slot_id) do
            Logger.warning(
              "Brewer slot #{slot_id} in project #{project_id} hit #{@max_fast_failures} fast failures, " <>
                "backing off #{div(@backoff_ms, 1000)}s before respawn"
            )

            timer =
              Process.send_after(
                self(),
                {:backoff_expired, project_id, slot_id},
                @backoff_ms
              )

            pool = put_in(pool.backoff_timers[slot_id], timer)
            put_pool(state, project_id, pool)
          else
            state = put_pool(state, project_id, pool)
            scale_project_agents(state, project_id)
          end
          end
        else
          Map.update!(state, :brewer_projects, &Map.delete(&1, pid))
        end
      else
        state
      end

    broadcast(state)
    {:noreply, state}
  end

  @impl true
  def handle_info({:backoff_expired, project_id, slot_id}, state) do
    Logger.info(
      "Backoff expired for slot #{slot_id} in project #{project_id}, attempting respawn"
    )

    state =
      case state.projects[project_id] do
        nil ->
          state

        pool ->
          pool = %{pool | backoff_timers: Map.delete(pool.backoff_timers, slot_id)}
          state = put_pool(state, project_id, pool)

          scale_project_agents(state, project_id)
      end

    broadcast(state)
    {:noreply, state}
  end

  # Private — Pool management

  defp new_pool do
    %{
      status: :paused,
      target_count: 0,
      agent_pids: [],
      idle_agents: [],
      agents: %{},
      failure_tracker: %{},
      backoff_timers: %{}
    }
  end

  defp get_or_create_pool(state, project_id) do
    state.projects[project_id] || new_pool()
  end

  defp put_pool(state, project_id, pool) do
    put_in(state.projects[project_id], pool)
  end

  # Private — Scheduling

  defp ensure_dispatch_scheduled(state) do
    unless state.dispatch_scheduled do
      schedule_dispatch()
    end
  end

  defp maybe_schedule_dispatch(state) do
    any_running? = Enum.any?(state.projects, fn {_id, pool} -> pool.status == :running end)

    if any_running? do
      schedule_dispatch()
      %{state | dispatch_scheduled: true}
    else
      %{state | dispatch_scheduled: false}
    end
  end

  defp schedule_dispatch do
    Process.send_after(self(), :dispatch, @dispatch_interval)
  end

  # Private — Scaling

  defp scale_project_agents(state, project_id) do
    pool = state.projects[project_id]
    if is_nil(pool) or pool.status == :paused, do: state, else: do_scale(state, project_id, pool)
  end

  defp do_scale(state, project_id, pool) do
    current = length(pool.agent_pids)
    target = pool.target_count

    cond do
      current < target ->
        {new_pids, next_id} = start_n_brewers(state.next_brewer_id, target - current)

        # Track project association for each new brewer
        new_mappings = Map.new(new_pids, fn pid -> {pid, project_id} end)

        pool = %{
          pool
          | agent_pids: pool.agent_pids ++ new_pids,
            idle_agents: pool.idle_agents ++ new_pids
        }

        %{
          state
          | next_brewer_id: next_id,
            brewer_projects: Map.merge(state.brewer_projects, new_mappings),
            projects: Map.put(state.projects, project_id, pool)
        }

      current > target ->
        {to_stop, to_keep} = Enum.split(pool.agent_pids, current - target)
        Enum.each(to_stop, &Apothecary.BrewerSupervisor.stop_brewer/1)

        pool = %{
          pool
          | agent_pids: to_keep,
            idle_agents: pool.idle_agents -- to_stop,
            agents: Map.drop(pool.agents, to_stop)
        }

        brewer_projects = Map.drop(state.brewer_projects, to_stop)

        %{
          state
          | brewer_projects: brewer_projects,
            projects: Map.put(state.projects, project_id, pool)
        }

      true ->
        state
    end
  end

  defp start_n_brewers(start_id, count) do
    pids =
      for id <- start_id..(start_id + count - 1) do
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

    {pids, start_id + count}
  end

  # Private — Dispatch

  defp try_dispatch(state) do
    Enum.reduce(state.projects, state, fn {project_id, pool}, acc ->
      if pool.status == :running and pool.idle_agents != [] do
        try_dispatch_project(acc, project_id)
      else
        acc
      end
    end)
  end

  defp try_dispatch_project(state, project_id) do
    case Apothecary.Worktrees.ready_worktrees(project_id: project_id) do
      [] ->
        state

      worktrees ->
        dispatch_first_available(worktrees, state, project_id)
    end
  end

  defp dispatch_first_available([], state, _project_id), do: state

  defp dispatch_first_available(_worktrees, state, project_id) do
    pool = state.projects[project_id]
    has_idle = not is_nil(pool) and pool.idle_agents != []
    if has_idle, do: do_dispatch(state, project_id), else: state
  end

  defp do_dispatch(state, project_id) do
    pool = state.projects[project_id]

    case Apothecary.Worktrees.ready_worktrees(project_id: project_id) do
      [] ->
        state

      [worktree | rest] ->
        # Skip questions — they are dispatched immediately via dispatch_question
        if worktree.kind == "question" do
          dispatch_remaining(rest, state, project_id)
        else
          agent_pid = if pool.idle_agents != [], do: hd(pool.idle_agents)

          if is_nil(agent_pid) do
            dispatch_remaining(rest, state, project_id)
          else
            brewer_state = pool.agents[agent_pid]
            brewer_id = if brewer_state, do: brewer_state.id, else: :erlang.phash2(agent_pid)

            case Apothecary.Worktrees.claim_worktree(worktree.id, brewer_id) do
              {:ok, claimed} ->
                project_dir = resolve_project_dir(worktree)

                case ensure_git_worktree(worktree, project_dir) do
                  {:ok, path, branch} ->
                    Apothecary.Worktrees.update_worktree(worktree.id, %{
                      git_path: path,
                      git_branch: branch
                    })

                    [_ | rest_idle] = pool.idle_agents
                    pool = %{pool | idle_agents: rest_idle}
                    state = put_pool(state, project_id, pool)

                    Apothecary.Brewer.assign_worktree(
                      agent_pid,
                      claimed,
                      path,
                      branch,
                      project_dir
                    )

                    state

                  {:error, reason} ->
                    Logger.error(
                      "Failed to create git worktree for #{worktree.id}: #{inspect(reason)}"
                    )

                    Apothecary.Worktrees.release_worktree(worktree.id)
                    dispatch_remaining(rest, state, project_id)
                end

              {:error, _} ->
                dispatch_remaining(rest, state, project_id)
            end
          end
        end
    end
  end

  defp dispatch_remaining([], state, _project_id), do: state

  defp dispatch_remaining(_rest, state, project_id) do
    # Retry dispatch for remaining worktrees
    do_dispatch(state, project_id)
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

  defp ensure_git_worktree(worktree, project_dir) do
    Apothecary.WorktreeManager.checkout(project_dir, worktree.id, title: worktree.title)
  end

  defp resolve_project_dir(%{project_id: project_id}) when not is_nil(project_id) do
    case Apothecary.Projects.get(project_id) do
      {:ok, project} -> project.path
      _ -> nil
    end
  end

  defp resolve_project_dir(_), do: nil

  # Private — Failure tracking (per-pool)

  defp record_pool_failure(pool, slot_id) do
    now = System.monotonic_time(:millisecond)

    entry =
      case pool.failure_tracker[slot_id] do
        %{count: count, first_failure: first} ->
          if now - first > @fast_failure_window_ms do
            %{count: 1, first_failure: now}
          else
            %{count: count + 1, first_failure: first}
          end

        nil ->
          %{count: 1, first_failure: now}
      end

    %{pool | failure_tracker: Map.put(pool.failure_tracker, slot_id, entry)}
  end

  defp should_pool_backoff?(pool, slot_id) do
    case pool.failure_tracker[slot_id] do
      %{count: count} when count >= @max_fast_failures -> true
      _ -> false
    end
  end

  # Private — Status building

  defp build_global_status(state) do
    # Aggregate across all projects for backward-compatible fields
    all_agents =
      Enum.reduce(state.projects, %{}, fn {_id, pool}, acc ->
        Map.merge(acc, pool.agents)
      end)

    total_target =
      Enum.reduce(state.projects, 0, fn {_id, pool}, acc -> acc + pool.target_count end)

    total_active =
      Enum.reduce(state.projects, 0, fn {_id, pool}, acc -> acc + length(pool.agent_pids) end)

    total_idle =
      Enum.reduce(state.projects, 0, fn {_id, pool}, acc -> acc + length(pool.idle_agents) end)

    any_running? = Enum.any?(state.projects, fn {_id, pool} -> pool.status == :running end)

    %{
      status: if(any_running?, do: :running, else: :paused),
      target_count: total_target,
      active_count: total_active,
      idle_count: total_idle,
      agents: all_agents,
      projects:
        Map.new(state.projects, fn {project_id, pool} ->
          {project_id, pool_status(pool)}
        end)
    }
  end

  defp build_project_status(state, project_id) do
    case state.projects[project_id] do
      nil -> pool_status(new_pool())
      pool -> pool_status(pool)
    end
  end

  defp pool_status(pool) do
    %{
      status: pool.status,
      target_count: pool.target_count,
      active_count: length(pool.agent_pids),
      idle_count: length(pool.idle_agents),
      agents: pool.agents
    }
  end

  # Private — Broadcast

  defp broadcast(state) do
    Phoenix.PubSub.broadcast(@pubsub, @topic, {:dispatcher_update, build_global_status(state)})
  end
end
