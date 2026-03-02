defmodule ApothecaryWeb.DashboardLive do
  use ApothecaryWeb, :live_view

  alias Apothecary.{Dispatcher, Poller}

  @stockroom_statuses MapSet.new(["open", "ready", "blocked"])
  @brewing_statuses MapSet.new(["in_progress"])
  @assaying_statuses MapSet.new(["pr_open", "revision_needed"])
  @bottled_statuses MapSet.new(["done", "closed", "merged"])

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      Poller.subscribe()
      Dispatcher.subscribe()
    end

    poller_state = Poller.get_state()
    dispatcher_status = Dispatcher.status()
    lanes = group_by_lane(poller_state.tasks)

    socket =
      socket
      |> assign(:page_title, "Dashboard")
      |> assign(:project_dir, poller_state.project_dir)
      |> assign(:stats, poller_state.stats)
      |> assign(:last_poll, poller_state.last_poll)
      |> assign(:error, poller_state.error)
      |> assign(:task_count, length(poller_state.tasks))
      |> assign(:swarm_status, dispatcher_status.status)
      |> assign(:target_count, max(dispatcher_status.target_count, 3))
      |> assign(:active_count, dispatcher_status.active_count)
      |> assign(:agents, Map.values(dispatcher_status.agents))
      |> assign(:bottled_collapsed, true)
      |> assign(:lane_counts, lane_counts(lanes))
      |> stream(:stockroom_tasks, lanes.stockroom)
      |> stream(:brewing_tasks, lanes.brewing)
      |> stream(:assaying_tasks, lanes.assaying)
      |> stream(:bottled_tasks, lanes.bottled)

    {:ok, socket}
  end

  @impl true
  def handle_info({:beads_update, state}, socket) do
    lanes = group_by_lane(state.tasks)

    socket =
      socket
      |> assign(:stats, state.stats)
      |> assign(:last_poll, state.last_poll)
      |> assign(:error, state.error)
      |> assign(:task_count, length(state.tasks))
      |> assign(:lane_counts, lane_counts(lanes))
      |> stream(:stockroom_tasks, lanes.stockroom, reset: true)
      |> stream(:brewing_tasks, lanes.brewing, reset: true)
      |> stream(:assaying_tasks, lanes.assaying, reset: true)
      |> stream(:bottled_tasks, lanes.bottled, reset: true)

    {:noreply, socket}
  end

  @impl true
  def handle_info({:dispatcher_update, status}, socket) do
    socket =
      socket
      |> assign(:swarm_status, status.status)
      |> assign(:target_count, status.target_count)
      |> assign(:active_count, status.active_count)
      |> assign(:agents, Map.values(status.agents))

    {:noreply, socket}
  end

  @impl true
  def handle_event("refresh", _params, socket) do
    Poller.force_refresh()
    {:noreply, socket}
  end

  @impl true
  def handle_event("toggle-bottled", _params, socket) do
    {:noreply, assign(socket, :bottled_collapsed, !socket.assigns.bottled_collapsed)}
  end

  @impl true
  def handle_event("start-swarm", _params, socket) do
    Dispatcher.start_swarm(socket.assigns.target_count)

    {:noreply,
     put_flash(socket, :info, "Swarm started with #{socket.assigns.target_count} agents")}
  end

  @impl true
  def handle_event("stop-swarm", _params, socket) do
    Dispatcher.stop_swarm()
    {:noreply, put_flash(socket, :info, "Swarm stopped")}
  end

  @impl true
  def handle_event("set-agent-count", %{"count" => count}, socket) do
    count = String.to_integer(count)

    if socket.assigns.swarm_status == :running do
      Dispatcher.set_agent_count(count)
    end

    {:noreply, assign(socket, :target_count, count)}
  end

  @impl true
  def handle_event("create-task", params, socket) do
    attrs = %{
      title: params["title"],
      type: params["type"],
      priority: params["priority"],
      description: if(params["description"] != "", do: params["description"])
    }

    case Apothecary.Beads.create(attrs) do
      {:ok, _} ->
        Poller.force_refresh()
        {:noreply, put_flash(socket, :info, "Task created")}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Failed to create task: #{inspect(reason)}")}
    end
  end

  defp group_by_lane(tasks) do
    result =
      Enum.reduce(tasks, %{stockroom: [], brewing: [], assaying: [], bottled: []}, fn task, acc ->
        cond do
          MapSet.member?(@stockroom_statuses, task.status) ->
            %{acc | stockroom: [task | acc.stockroom]}

          MapSet.member?(@brewing_statuses, task.status) ->
            %{acc | brewing: [task | acc.brewing]}

          MapSet.member?(@assaying_statuses, task.status) ->
            %{acc | assaying: [task | acc.assaying]}

          MapSet.member?(@bottled_statuses, task.status) ->
            %{acc | bottled: [task | acc.bottled]}

          true ->
            %{acc | stockroom: [task | acc.stockroom]}
        end
      end)

    Map.new(result, fn {k, v} -> {k, Enum.reverse(v)} end)
  end

  defp lane_counts(lanes) do
    %{
      stockroom: length(lanes.stockroom),
      brewing: length(lanes.brewing),
      assaying: length(lanes.assaying),
      bottled: length(lanes.bottled)
    }
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <div class="space-y-5">
        <%!-- Header --%>
        <div class="flex items-center justify-between">
          <div>
            <h1 class="text-xl font-bold">Apothecary</h1>
            <p :if={@project_dir} class="text-sm text-base-content/50 truncate max-w-lg">
              {@project_dir}
            </p>
          </div>
          <div class="flex items-center gap-2">
            <span :if={@error} class="text-xs text-error">{@error}</span>
            <span :if={@last_poll} class="text-xs text-base-content/40">
              Last poll: {Calendar.strftime(@last_poll, "%H:%M:%S")}
            </span>
            <button phx-click="refresh" class="btn btn-sm btn-ghost">
              <.icon name="hero-arrow-path" class="size-4" />
            </button>
          </div>
        </div>

        <%!-- Stats --%>
        <.stats_bar
          stats={@stats}
          last_poll={@last_poll}
          task_count={@task_count}
          agent_count={@active_count}
          ready_count={@lane_counts.stockroom}
        />

        <%!-- Kanban Board --%>
        <div class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-4">
          <%!-- Stockroom --%>
          <.lane_column title="Stockroom" count={@lane_counts.stockroom} color="info">
            <div id="stockroom-tasks" phx-update="stream" class="space-y-2">
              <div
                id="stockroom-empty"
                class="hidden only:block text-xs text-base-content/40 text-center py-6"
              >
                No tasks waiting
              </div>
              <div :for={{id, task} <- @streams.stockroom_tasks} id={id}>
                <.task_card task={task} />
              </div>
            </div>
          </.lane_column>

          <%!-- Brewing --%>
          <.lane_column title="Brewing" count={@lane_counts.brewing} color="warning">
            <div id="brewing-tasks" phx-update="stream" class="space-y-2">
              <div
                id="brewing-empty"
                class="hidden only:block text-xs text-base-content/40 text-center py-6"
              >
                No active work
              </div>
              <div :for={{id, task} <- @streams.brewing_tasks} id={id}>
                <.task_card task={task} />
              </div>
            </div>
          </.lane_column>

          <%!-- Assaying --%>
          <.lane_column title="Assaying" count={@lane_counts.assaying} color="secondary">
            <div id="assaying-tasks" phx-update="stream" class="space-y-2">
              <div
                id="assaying-empty"
                class="hidden only:block text-xs text-base-content/40 text-center py-6"
              >
                Nothing in review
              </div>
              <div :for={{id, task} <- @streams.assaying_tasks} id={id}>
                <.task_card task={task} />
              </div>
            </div>
          </.lane_column>

          <%!-- Bottled (collapsed by default) --%>
          <.lane_column
            title="Bottled"
            count={@lane_counts.bottled}
            color="success"
            collapsed={@bottled_collapsed}
            toggle_event="toggle-bottled"
          >
            <div id="bottled-tasks" phx-update="stream" class="space-y-2">
              <div
                id="bottled-empty"
                class="hidden only:block text-xs text-base-content/40 text-center py-6"
              >
                Nothing completed yet
              </div>
              <div :for={{id, task} <- @streams.bottled_tasks} id={id}>
                <.task_card task={task} />
              </div>
            </div>
          </.lane_column>
        </div>

        <%!-- Controls and Agents --%>
        <div class="grid grid-cols-1 lg:grid-cols-3 gap-4">
          <.swarm_controls
            swarm_status={@swarm_status}
            target_count={@target_count}
            active_count={@active_count}
          />

          <.create_task_form />

          <div class="space-y-2">
            <h3 class="font-semibold">Active Agents</h3>
            <%= if @agents == [] do %>
              <div class="bg-base-200 rounded-box p-4 text-sm text-base-content/50">
                No agents running
              </div>
            <% else %>
              <.agent_card :for={agent <- @agents} agent={agent} />
            <% end %>
          </div>
        </div>
      </div>
    </Layouts.app>
    """
  end
end
