defmodule ApothecaryWeb.AgentLive do
  use ApothecaryWeb, :live_view

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    agent_id = String.to_integer(id)

    if connected?(socket) do
      Phoenix.PubSub.subscribe(Apothecary.PubSub, "agent:#{agent_id}")
    end

    # Get initial state from dispatcher
    dispatcher_status = Apothecary.Dispatcher.status()

    agent =
      dispatcher_status.agents
      |> Map.values()
      |> Enum.find(fn a -> a.id == agent_id end)

    socket =
      socket
      |> assign(:page_title, "Agent #{agent_id}")
      |> assign(:agent_id, agent_id)
      |> assign(:agent, agent)
      |> assign(:output, (agent && agent.output) || [])

    {:ok, socket}
  end

  @impl true
  def handle_info({:agent_state, agent}, socket) do
    {:noreply, assign(socket, :agent, agent)}
  end

  @impl true
  def handle_info({:agent_output, lines}, socket) do
    output = socket.assigns.output ++ lines
    {:noreply, assign(socket, :output, Enum.take(output, -500))}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <div class="space-y-6">
        <div class="flex items-center gap-4">
          <.link navigate={~p"/"} class="btn btn-ghost btn-sm">
            <.icon name="hero-arrow-left" class="size-4" /> Back
          </.link>
          <h1 class="text-xl font-bold">Agent {@agent_id}</h1>
          <.agent_status_badge :if={@agent} status={@agent.status} />
        </div>

        <%= if @agent do %>
          <div class="grid grid-cols-1 md:grid-cols-3 gap-4">
            <div class="bg-base-200 rounded-box p-4">
              <div class="text-xs text-base-content/50">Status</div>
              <div class="font-semibold">{Atom.to_string(@agent.status)}</div>
            </div>
            <div class="bg-base-200 rounded-box p-4">
              <div class="text-xs text-base-content/50">Branch</div>
              <div class="font-semibold truncate">{@agent.branch || "—"}</div>
            </div>
            <div class="bg-base-200 rounded-box p-4">
              <div class="text-xs text-base-content/50">Current Task</div>
              <div class="font-semibold">
                <%= if @agent.current_task do %>
                  <.link navigate={~p"/tasks/#{@agent.current_task.id}"} class="link">
                    {@agent.current_task.id}
                  </.link>
                <% else %>
                  —
                <% end %>
              </div>
            </div>
          </div>
        <% end %>

        <div class="space-y-2">
          <h2 class="font-semibold">Output</h2>
          <div
            id="agent-output"
            phx-hook="ScrollBottom"
            class="bg-base-300 rounded-box p-4 font-mono text-xs h-[60vh] overflow-y-auto whitespace-pre-wrap"
          >
            <%= if @output == [] do %>
              <span class="text-base-content/40">Waiting for output...</span>
            <% else %>
              <%= for line <- @output do %>
                <div>{line}</div>
              <% end %>
            <% end %>
          </div>
        </div>
      </div>
    </Layouts.app>
    """
  end
end
