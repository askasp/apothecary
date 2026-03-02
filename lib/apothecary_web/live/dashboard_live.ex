defmodule ApothecaryWeb.DashboardLive do
  use ApothecaryWeb, :live_view

  alias Apothecary.{Dispatcher, Poller}

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      Poller.subscribe()
      Dispatcher.subscribe()
    end

    poller_state = Poller.get_state()
    dispatcher_status = Dispatcher.status()

    socket =
      socket
      |> assign(:page_title, "Dashboard")
      |> assign(:project_dir, poller_state.project_dir)
      |> assign(:stats, poller_state.stats)
      |> assign(:ready_tasks, poller_state.ready_tasks)
      |> assign(:last_poll, poller_state.last_poll)
      |> assign(:error, poller_state.error)
      |> assign(:filter, "all")
      |> assign(:task_count, length(poller_state.tasks))
      |> assign(:swarm_status, dispatcher_status.status)
      |> assign(:target_count, max(dispatcher_status.target_count, 3))
      |> assign(:active_count, dispatcher_status.active_count)
      |> assign(:agents, Map.values(dispatcher_status.agents))
      |> stream(:tasks, poller_state.tasks)

    {:ok, socket}
  end

  @impl true
  def handle_info({:beads_update, state}, socket) do
    filtered = filter_tasks(state.tasks, socket.assigns.filter)

    socket =
      socket
      |> assign(:stats, state.stats)
      |> assign(:ready_tasks, state.ready_tasks)
      |> assign(:last_poll, state.last_poll)
      |> assign(:error, state.error)
      |> assign(:task_count, length(state.tasks))
      |> stream(:tasks, filtered, reset: true)

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
  def handle_event("filter", %{"filter" => filter}, socket) do
    poller_state = Poller.get_state()
    filtered = filter_tasks(poller_state.tasks, filter)

    socket =
      socket
      |> assign(:filter, filter)
      |> stream(:tasks, filtered, reset: true)

    {:noreply, socket}
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

  defp filter_tasks(tasks, "all"), do: tasks
  defp filter_tasks(tasks, "ready"), do: Enum.filter(tasks, &(&1.status in ["ready", "open"]))
  defp filter_tasks(tasks, "in_progress"), do: Enum.filter(tasks, &(&1.status == "in_progress"))
  defp filter_tasks(tasks, "done"), do: Enum.filter(tasks, &(&1.status in ["done", "closed"]))
  defp filter_tasks(tasks, "blocked"), do: Enum.filter(tasks, &(&1.status == "blocked"))
  defp filter_tasks(tasks, _), do: tasks

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <div class="space-y-6">
        <%!-- Header --%>
        <div class="flex items-center justify-between">
          <div>
            <h1 class="text-2xl font-bold tracking-tight">Apothecary</h1>
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
          ready_count={length(@ready_tasks)}
        />

        <div class="grid grid-cols-1 lg:grid-cols-3 gap-6">
          <%!-- Concoction Board (2/3) --%>
          <div class="lg:col-span-2 space-y-4">
            <div class="flex items-center justify-between">
              <h2 class="text-lg font-semibold">Concoctions</h2>
              <div class="flex gap-1 flex-wrap">
                <button
                  :for={
                    {label, f} <- [
                      {"All", "all"},
                      {"Ready", "ready"},
                      {"Simmering", "in_progress"},
                      {"Brewed", "done"},
                      {"Blocked", "blocked"}
                    ]
                  }
                  phx-click="filter"
                  phx-value-filter={f}
                  class={["btn btn-xs", if(@filter == f, do: "btn-primary", else: "btn-ghost")]}
                >
                  {label}
                </button>
              </div>
            </div>

            <div id="tasks" phx-update="stream" class="space-y-3">
              <div id="tasks-empty" class="hidden only:block text-base-content/50 text-center py-12">
                The cauldron is empty. Add an ingredient to start brewing.
              </div>
              <div :for={{id, task} <- @streams.tasks} id={id}>
                <.task_card task={task} />
              </div>
            </div>
          </div>

          <%!-- Sidebar (1/3) --%>
          <div class="space-y-4">
            <.swarm_controls
              swarm_status={@swarm_status}
              target_count={@target_count}
              active_count={@active_count}
            />

            <div :if={@agents != []} class="space-y-3">
              <h3 class="font-semibold">Active Brewers</h3>
              <.agent_card :for={agent <- @agents} agent={agent} />
            </div>

            <.create_task_form />

            <div :if={@ready_tasks != []} class="bg-base-200 rounded-box p-5 space-y-2">
              <h3 class="font-semibold text-sm">Ready Queue</h3>
              <div :for={task <- Enum.take(@ready_tasks, 10)} class="text-sm py-0.5">
                <.link navigate={~p"/tasks/#{task.id}"} class="hover:underline truncate block">
                  <span class="text-base-content/40 font-mono">{task.id}</span>
                  <span class="ml-1">{task.title}</span>
                </.link>
              </div>
            </div>
          </div>
        </div>
      </div>
    </Layouts.app>
    """
  end
end
