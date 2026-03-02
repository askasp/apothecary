defmodule ApothecaryWeb.DashboardComponents do
  @moduledoc "Function components for the swarm dashboard."
  use Phoenix.Component

  import ApothecaryWeb.CoreComponents, only: [icon: 1]

  use Phoenix.VerifiedRoutes,
    endpoint: ApothecaryWeb.Endpoint,
    router: ApothecaryWeb.Router,
    statics: ApothecaryWeb.static_paths()

  # Stats bar

  attr :stats, :map, required: true
  attr :last_poll, :any, default: nil
  attr :task_count, :integer, default: 0
  attr :agent_count, :integer, default: 0
  attr :ready_count, :integer, default: 0

  def stats_bar(assigns) do
    ~H"""
    <div class="grid grid-cols-2 md:grid-cols-5 gap-3">
      <div class="bg-base-200 rounded-box p-4">
        <div class="text-xs text-base-content/50">Ingredients</div>
        <div class="text-2xl font-bold">{@task_count}</div>
      </div>
      <div class="bg-base-200 rounded-box p-4">
        <div class="text-xs text-base-content/50">Ready</div>
        <div class="text-2xl font-bold text-info">{@ready_count}</div>
      </div>
      <div class="bg-base-200 rounded-box p-4">
        <div class="text-xs text-base-content/50">Simmering</div>
        <div class="text-2xl font-bold text-warning">{@stats["in_progress"] || 0}</div>
      </div>
      <div class="bg-base-200 rounded-box p-4">
        <div class="text-xs text-base-content/50">Brewed</div>
        <div class="text-2xl font-bold text-success">
          {@stats["completed"] || @stats["closed"] || 0}
        </div>
      </div>
      <div class="bg-base-200 rounded-box p-4">
        <div class="text-xs text-base-content/50">Brewers</div>
        <div class="text-2xl font-bold text-primary">{@agent_count}</div>
      </div>
    </div>
    """
  end

  # Task card

  attr :task, :map, required: true

  def task_card(assigns) do
    ~H"""
    <div class={[
      "bg-base-200 rounded-box p-5 hover:bg-base-300 transition-colors",
      @task.status == "in_progress" && "concoction-simmering border border-warning/20"
    ]}>
      <div class="flex items-start justify-between gap-3">
        <div class="space-y-2 min-w-0 flex-1">
          <div class="flex items-center gap-2 flex-wrap">
            <.status_badge status={@task.status} />
            <.priority_badge priority={@task.priority} />
            <span :if={@task.type} class="text-xs text-base-content/50">{@task.type}</span>
            <span
              :if={@task.status == "in_progress"}
              class="flex items-center gap-1 text-xs text-warning"
            >
              <span class="stir-icon">~</span>
              stirring
              <span class="flex gap-0.5">
                <span class="bubble-dot inline-block w-1 h-1 rounded-full bg-warning"></span>
                <span class="bubble-dot inline-block w-1 h-1 rounded-full bg-warning"></span>
                <span class="bubble-dot inline-block w-1 h-1 rounded-full bg-warning"></span>
              </span>
            </span>
          </div>
          <.link navigate={~p"/tasks/#{@task.id}"} class="font-medium hover:underline block">
            <span class="text-base-content/40 text-sm font-mono">{@task.id}</span>
            <span class="ml-1.5 text-base">{@task.title}</span>
          </.link>
          <p :if={@task.description} class="text-sm text-base-content/60 line-clamp-2 mt-1">
            {@task.description}
          </p>
        </div>
        <div :if={@task.assigned_to} class="badge badge-sm badge-info shrink-0">
          {@task.assigned_to}
        </div>
      </div>
    </div>
    """
  end

  # Agent card

  attr :agent, :map, required: true

  def agent_card(assigns) do
    ~H"""
    <div class={[
      "bg-base-200 rounded-box p-5 space-y-3",
      @agent.status == :working && "border border-success/20"
    ]}>
      <div class="flex items-center justify-between">
        <span class="font-semibold">Brewer {@agent.id}</span>
        <.agent_status_badge status={@agent.status} />
      </div>
      <div :if={@agent.branch} class="text-sm text-base-content/50 font-mono truncate">
        <.icon name="hero-code-bracket" class="size-3.5 inline" /> {@agent.branch}
      </div>
      <div :if={@agent.current_task} class="text-sm">
        <span class="text-base-content/60">Brewing:</span>
        <.link navigate={~p"/tasks/#{@agent.current_task.id}"} class="link font-medium">
          {@agent.current_task.id}
        </.link>
        <span :if={@agent.status == :working} class="ml-1 stir-icon text-warning">~</span>
      </div>
      <div
        :if={@agent.output != []}
        class="text-xs text-base-content/50 font-mono bg-base-300 rounded p-2 truncate"
      >
        {List.last(@agent.output)}
      </div>
    </div>
    """
  end

  # Status badge

  attr :status, :string, default: nil

  def status_badge(assigns) do
    ~H"""
    <span class={["badge badge-sm", status_class(@status)]}>
      {@status || "unknown"}
    </span>
    """
  end

  defp status_class(nil), do: "badge-ghost"
  defp status_class("open"), do: "badge-info"
  defp status_class("ready"), do: "badge-info"
  defp status_class("in_progress"), do: "badge-warning"
  defp status_class("done"), do: "badge-success"
  defp status_class("closed"), do: "badge-success"
  defp status_class("blocked"), do: "badge-error"
  defp status_class(_), do: "badge-ghost"

  # Priority badge

  attr :priority, :any, default: nil

  def priority_badge(assigns) do
    ~H"""
    <span :if={@priority} class={["badge badge-sm badge-outline", priority_class(@priority)]}>
      P{@priority}
    </span>
    """
  end

  defp priority_class(0), do: "badge-error"
  defp priority_class(1), do: "badge-warning"
  defp priority_class(2), do: ""
  defp priority_class(3), do: "badge-info"
  defp priority_class(_), do: ""

  # Agent status badge

  attr :status, :atom, default: :idle

  def agent_status_badge(assigns) do
    ~H"""
    <span class={["badge badge-sm", agent_status_class(@status)]}>
      {agent_status_label(@status)}
    </span>
    """
  end

  defp agent_status_class(:working), do: "badge-success"
  defp agent_status_class(:idle), do: "badge-ghost"
  defp agent_status_class(:starting), do: "badge-info"
  defp agent_status_class(:error), do: "badge-error"
  defp agent_status_class(_), do: "badge-ghost"

  defp agent_status_label(:working), do: "brewing"
  defp agent_status_label(:idle), do: "idle"
  defp agent_status_label(:starting), do: "lighting fire"
  defp agent_status_label(:error), do: "error"
  defp agent_status_label(status), do: Atom.to_string(status)

  # Swarm control panel

  attr :swarm_status, :atom, default: :paused
  attr :target_count, :integer, default: 3
  attr :active_count, :integer, default: 0

  def swarm_controls(assigns) do
    ~H"""
    <div class="bg-base-200 rounded-box p-4 space-y-3">
      <div class="flex items-center justify-between">
        <h3 class="font-semibold">Brew Control</h3>
        <span class={[
          "badge badge-sm",
          if(@swarm_status == :running, do: "badge-success", else: "badge-ghost")
        ]}>
          {Atom.to_string(@swarm_status)}
        </span>
      </div>

      <div class="flex items-center gap-3">
        <label class="text-sm text-base-content/70">Brewers:</label>
        <input
          type="range"
          min="1"
          max="10"
          value={@target_count}
          class="range range-sm range-primary flex-1"
          phx-change="set-agent-count"
          name="count"
        />
        <span class="text-sm font-mono w-6 text-center">{@target_count}</span>
      </div>

      <div class="flex gap-2">
        <%= if @swarm_status == :paused do %>
          <button phx-click="start-swarm" class="btn btn-sm btn-primary flex-1">
            <.icon name="hero-play" class="size-4" /> Start Brewing
          </button>
        <% else %>
          <button phx-click="stop-swarm" class="btn btn-sm btn-error btn-soft flex-1">
            <.icon name="hero-stop" class="size-4" /> Stop Brewing
          </button>
        <% end %>
      </div>
    </div>
    """
  end

  # Create task form

  attr :form, :any, default: nil

  def create_task_form(assigns) do
    ~H"""
    <div class="bg-base-200 rounded-box p-5 space-y-3">
      <h3 class="font-semibold">Add Ingredient</h3>
      <.form for={%{}} phx-submit="create-task" id="create-task-form" class="space-y-3">
        <input
          type="text"
          name="title"
          placeholder="What needs brewing..."
          required
          class="input w-full"
        />
        <div class="flex gap-2">
          <select name="type" class="select select-sm flex-1">
            <option value="task">Task</option>
            <option value="bug">Bug</option>
            <option value="feature">Feature</option>
            <option value="epic">Epic</option>
          </select>
          <select name="priority" class="select select-sm w-20">
            <option value="0">P0</option>
            <option value="1">P1</option>
            <option value="2" selected>P2</option>
            <option value="3">P3</option>
          </select>
        </div>
        <textarea
          name="description"
          placeholder="Describe the ingredient in detail (optional)"
          rows="6"
          class="textarea w-full text-sm leading-relaxed"
        />
        <button type="submit" class="btn btn-sm btn-primary w-full">
          <.icon name="hero-plus" class="size-4" /> Add to Cauldron
        </button>
      </.form>
    </div>
    """
  end
end
