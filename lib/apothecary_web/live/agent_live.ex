defmodule ApothecaryWeb.AgentLive do
  use ApothecaryWeb, :live_view

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    agent_id = String.to_integer(id)

    if connected?(socket) do
      Phoenix.PubSub.subscribe(Apothecary.PubSub, "brewer:#{agent_id}")
    end

    # Get initial state from dispatcher
    dispatcher_status = Apothecary.Dispatcher.status()

    agent =
      dispatcher_status.agents
      |> Map.values()
      |> Enum.find(fn a -> a.id == agent_id end)

    socket =
      socket
      |> assign(:page_title, "Brewer #{agent_id}")
      |> assign(:agent_id, agent_id)
      |> assign(:agent, agent)
      |> assign(:output, (agent && agent.output) || [])
      |> assign(:show_help, false)

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

  # Hotkey dispatch — ignore OS shortcuts (Cmd/Ctrl+key) so copy/paste works
  @impl true
  def handle_event("hotkey", %{"metaKey" => true}, socket), do: {:noreply, socket}
  def handle_event("hotkey", %{"ctrlKey" => true}, socket), do: {:noreply, socket}

  def handle_event("hotkey", %{"key" => key}, socket) do
    {:noreply, handle_hotkey(key, socket)}
  end

  @impl true
  def handle_event("close-help", _params, socket),
    do: {:noreply, assign(socket, :show_help, false)}

  defp handle_hotkey("?", socket), do: assign(socket, :show_help, !socket.assigns.show_help)
  defp handle_hotkey("Escape", socket), do: assign(socket, :show_help, false)
  defp handle_hotkey("Backspace", socket), do: push_navigate(socket, to: ~p"/")
  defp handle_hotkey(_key, socket), do: socket

  defp agent_color(:working), do: "text-green-400"
  defp agent_color(:idle), do: "text-yellow-400"
  defp agent_color(:starting), do: "text-cyan-400"
  defp agent_color(:error), do: "text-red-400"
  defp agent_color(_), do: "text-base-content/30"

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <div class="mx-auto max-w-6xl px-4 py-3 space-y-3">
        <div
          id="hotkey-root"
          phx-window-keydown="hotkey"
          phx-keydown="hotkey"
          tabindex="0"
          phx-throttle="100"
          class="space-y-3 outline-none"
        >
          <div class="flex items-center gap-3 text-base-content/30">
            <.link navigate={~p"/"} class="hover:text-base-content/50">[bksp:back]</.link>
            <span class="text-base-content/50">BREWER {@agent_id}</span>
            <.agent_status_badge :if={@agent} status={@agent.status} />
          </div>

          <%= if @agent do %>
            <div class="flex items-center gap-4 text-xs flex-wrap">
              <span class="text-base-content/40">
                status:
                <span class={agent_color(@agent.status)}>{Atom.to_string(@agent.status)}</span>
              </span>
              <span class="text-base-content/40">
                branch: <span class="text-base-content/60">{@agent.branch || "—"}</span>
              </span>
              <span class="text-base-content/40">
                worktree:
                <%= if @agent.current_worktree do %>
                  <.link
                    navigate={~p"/tasks/#{@agent.current_worktree.id}"}
                    class="text-cyan-400 hover:text-cyan-300"
                  >
                    {@agent.current_worktree.id}
                  </.link>
                <% else %>
                  <span class="text-base-content/30">—</span>
                <% end %>
              </span>
            </div>
          <% end %>

          <div class="space-y-1">
            <div class="flex items-center gap-2">
              <div class="flex-1"><.section label="output" /></div>
              <.copy_button :if={@output != []} target="#agent-output" />
            </div>
            <div
              id="agent-output"
              phx-hook="ScrollBottom"
              class="bg-base-300/50 border border-base-content/5 p-2 text-xs h-[70vh] overflow-y-auto whitespace-pre-wrap"
            >
              <%= if @output == [] do %>
                <span class="text-base-content/30">waiting for output...</span>
              <% else %>
                <%= for line <- @output do %>
                  <div class="text-base-content/70">{line}</div>
                <% end %>
              <% end %>
            </div>
          </div>
        </div>

        <.which_key_overlay :if={@show_help} page={:agent} />
        <.status_bar page={:agent} />
      </div>
    </Layouts.app>
    """
  end
end
