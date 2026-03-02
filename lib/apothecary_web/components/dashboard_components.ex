defmodule ApothecaryWeb.DashboardComponents do
  @moduledoc "Card-based function components for the swarm dashboard."
  use Phoenix.Component

  use Phoenix.VerifiedRoutes,
    endpoint: ApothecaryWeb.Endpoint,
    router: ApothecaryWeb.Router,
    statics: ApothecaryWeb.static_paths()

  # --- Status Controls (full-width header bar) ---

  attr :swarm_status, :atom, default: :paused
  attr :target_count, :integer, default: 3
  attr :active_count, :integer, default: 0
  attr :working_count, :integer, default: 0

  def status_controls(assigns) do
    ~H"""
    <div class="flex items-center gap-3 px-2 py-2 text-xs flex-wrap">
      <span class="font-apothecary text-sm font-bold tracking-wide text-base-content/80">
        Apothecary
      </span>

      <%= if @swarm_status == :running do %>
        <button
          phx-click="stop-swarm"
          class="flex items-center gap-2 border border-base-content/20 hover:border-base-content/40 text-base-content/70 hover:text-base-content px-3 py-1.5 rounded cursor-pointer font-apothecary text-sm transition-colors"
          title="Click to stop brewing (s)"
        >
          <span class="cauldron-stir text-xl">&#x2697;</span>
          <span class="text-base">Brewing</span>
          <span class="text-base-content/30 text-xs ml-1">[s]</span>
        </button>
      <% else %>
        <button
          phx-click="start-swarm"
          class="flex items-center gap-2 border border-base-content/15 hover:border-base-content/30 text-base-content/40 hover:text-base-content/70 px-3 py-1.5 rounded cursor-pointer font-apothecary text-sm transition-colors"
          title="Click to start brewing (s)"
        >
          <span class="text-xl">&#x2697;</span>
          <span class="text-base">Brew</span>
          <span class="text-base-content/30 text-xs ml-1">[s]</span>
        </button>
      <% end %>

      <span class="text-base-content/20">│</span>

      <div class="flex items-center gap-1">
        <button
          phx-click="dec-agents"
          class="text-base-content/50 hover:text-base-content cursor-pointer px-1"
        >
          -
        </button>
        <span class="text-base-content/50">{@target_count} brewers</span>
        <button
          phx-click="inc-agents"
          class="text-base-content/50 hover:text-base-content cursor-pointer px-1"
        >
          +
        </button>
      </div>

      <span class="ml-auto text-base-content/30 cursor-pointer" phx-click="toggle-help">?</span>
    </div>
    """
  end

  # --- Primary Input (big textarea at top) ---

  attr :input_focused, :boolean, default: false

  def primary_input(assigns) do
    ~H"""
    <div>
      <textarea
        id="primary-input"
        rows="5"
        placeholder=""
        phx-hook="TextareaSubmit"
        phx-focus="input-focus"
        phx-blur="input-blur"
        autocomplete="off"
        class="bg-transparent border border-base-content/20 focus:border-primary outline-none px-3 py-2 text-sm w-full resize-none rounded-lg"
      ></textarea>
    </div>
    """
  end

  # --- Activity Ticker (single row of agent dots) ---

  attr :agents, :list, default: []

  def activity_ticker(assigns) do
    ~H"""
    <div
      :if={@agents != []}
      class="flex items-center gap-3 px-3 py-1 text-xs overflow-x-auto"
    >
      <span
        :for={agent <- @agents}
        class="flex items-center gap-1 shrink-0"
      >
        <span class={agent_dot_color(agent.status)}>{agent_dot(agent.status)}</span>
        <span class="text-base-content/50">B{agent.id}</span>
        <span :if={agent.current_concoction} class="text-base-content/40 truncate max-w-32">
          "{agent.current_concoction.title || agent.current_concoction.id}"
        </span>
        <span :if={!agent.current_concoction} class="text-base-content/30">resting</span>
      </span>
    </div>
    """
  end

  # --- Worktree Group Header (section divider with collapse) ---

  attr :label, :string, required: true
  attr :count, :integer, required: true
  attr :color, :string, required: true
  attr :group, :string, required: true
  attr :collapsed, :boolean, default: false
  attr :collapsible, :boolean, default: false

  def worktree_group_header(assigns) do
    ~H"""
    <button
      :if={@collapsible}
      phx-click="toggle-done-collapse"
      class="flex items-center gap-2 px-3 py-1.5 w-full text-left cursor-pointer hover:bg-base-content/5"
    >
      <span class="w-3 text-base-content/30">{if(@collapsed, do: "▸", else: "▾")}</span>
      <span class={["uppercase text-xs tracking-wider font-bold font-apothecary", @color]}>
        {@label}
      </span>
      <span class="text-base-content/30 text-xs">({@count})</span>
    </button>
    <div
      :if={!@collapsible}
      class="flex items-center gap-2 px-3 py-1.5"
    >
      <span class="w-3 text-base-content/30">▾</span>
      <span class={["uppercase text-xs tracking-wider font-bold font-apothecary", @color]}>
        {@label}
      </span>
      <span class="text-base-content/30 text-xs">({@count})</span>
    </div>
    """
  end

  # --- Worktree Card ---

  attr :worktree, :map, required: true
  attr :tasks, :list, default: []
  attr :agent, :map, default: nil
  attr :dev_server, :map, default: nil
  attr :selected, :boolean, default: false
  attr :group, :string, default: nil

  def worktree_card(assigns) do
    done_count = Enum.count(assigns.tasks, &(&1.status in ["done", "closed"]))
    total_count = length(assigns.tasks)
    progress_pct = if total_count > 0, do: round(done_count / total_count * 100), else: 0

    assigns =
      assigns
      |> assign(:done_count, done_count)
      |> assign(:total_count, total_count)
      |> assign(:progress_pct, progress_pct)

    ~H"""
    <div
      data-card-id={@worktree.id}
      data-selected={@selected || nil}
      class={[
        "border bg-base-200/30 flex flex-col relative overflow-hidden scroll-card rounded-xl",
        if(@selected,
          do: "border-primary ring-1 ring-primary/50",
          else: "border-base-content/10 hover:border-base-content/20"
        )
      ]}
    >
      <%!-- Card header --%>
      <.link
        patch={~p"/?task=#{@worktree.id}"}
        class="px-3 pt-2 pb-1 cursor-pointer hover:bg-base-content/5"
      >
        <div class={["text-sm font-bold", status_color(@worktree.status)]}>
          {@worktree.title || @worktree.id}
        </div>
        <div class="flex items-center gap-2 text-xs text-base-content/40 mt-0.5">
          <span>{@worktree.id}</span>
          <span :if={@worktree.git_branch} class="truncate">⎇ {@worktree.git_branch}</span>
          <span
            :if={@group}
            class={[
              "text-[10px] uppercase tracking-wider px-1.5 py-0.5 font-bold",
              group_badge_classes(@group)
            ]}
          >
            {group_badge_label(@group)}
          </span>
          <span :if={@agent} class="text-cyan-400 shrink-0">
            {agent_dot(@agent.status)}B{@agent.id}
          </span>
        </div>
      </.link>

      <%!-- Inline add task --%>
      <div class="px-3 pb-1 pt-1">
        <.form
          for={%{}}
          phx-submit="create-card-task"
          class="flex items-center gap-1"
        >
          <input type="hidden" name="concoction_id" value={@worktree.id} />
          <input
            type="text"
            name="title"
            placeholder="+ add ingredient..."
            phx-focus="input-focus"
            phx-blur="input-blur"
            autocomplete="off"
            phx-hook="InlineSubmit"
            id={"card-input-#{@worktree.id}"}
            class="bg-transparent border-b border-base-content/10 focus:border-primary outline-none px-1 py-1 text-sm flex-1 min-w-0"
          />
        </.form>
      </div>

      <%!-- Task checklist --%>
      <div :if={@tasks != []} class="px-3 py-1 space-y-1 text-xs">
        <div
          :for={task <- Enum.take(@tasks, 8)}
          id={"ingredient-#{task.id}"}
          phx-mounted={Phoenix.LiveView.JS.transition("ingredient-new")}
          class="flex items-center gap-1.5 py-0.5"
        >
          <%= cond do %>
            <% task.status in ["done", "closed"] -> %>
              <span class="text-green-400">✓</span>
            <% task.status == "in_progress" -> %>
              <span class="text-amber-400 cauldron-stir">&#x2697;</span>
            <% true -> %>
              <span class="text-base-content/30">□</span>
          <% end %>
          <.link
            patch={~p"/?task=#{task.id}"}
            class={[
              "truncate hover:text-primary cursor-pointer",
              cond do
                task.status in ["done", "closed"] -> "text-base-content/30 line-through"
                task.status == "in_progress" -> "text-amber-400"
                true -> "text-base-content/70"
              end
            ]}
          >
            {task.title}
          </.link>
        </div>
        <div :if={length(@tasks) > 8} class="text-base-content/30">
          +{length(@tasks) - 8} more...
        </div>
      </div>

      <%!-- Progress bar --%>
      <div :if={@total_count > 0} class="px-3 py-1">
        <div class="flex items-center gap-2 text-xs">
          <div class="flex-1 bg-base-content/10 h-1">
            <div
              class="bg-green-400 h-1 transition-all"
              style={"width: #{@progress_pct}%"}
            />
          </div>
          <span class="text-base-content/40 shrink-0">{@done_count}/{@total_count}</span>
        </div>
      </div>

      <%!-- Preview indicator (only visible when active) --%>
      <.preview_indicator worktree_id={@worktree.id} dev_server={@dev_server} />

      <%!-- Large flask overlay for actively brewing cards --%>
      <span
        :if={@agent && @agent.status == :working}
        class="absolute bottom-1 right-2 text-5xl text-amber-400/20 brew-icon pointer-events-none select-none"
      >
        &#x2697;
      </span>
    </div>
    """
  end

  # --- Preview Indicator (on worktree card, only shown when active) ---

  attr :worktree_id, :string, required: true
  attr :dev_server, :map, default: nil

  def preview_indicator(%{dev_server: %{status: :starting}} = assigns) do
    ~H"""
    <div class="px-3 py-1 flex items-center gap-2 text-xs">
      <span class="text-cyan-400">PREVIEW</span>
      <span class="text-cyan-400 animate-pulse">◐ starting...</span>
    </div>
    """
  end

  def preview_indicator(%{dev_server: %{status: :running}} = assigns) do
    ~H"""
    <div class="px-3 py-1 flex items-center gap-2 text-xs flex-wrap">
      <span class="text-green-400">PREVIEW ●</span>
      <span :for={p <- @dev_server.ports} class="shrink-0">
        <a
          href={"http://localhost:#{p.port}"}
          target="_blank"
          class="text-cyan-400 hover:text-cyan-300"
        >
          {p.name}:{p.port}
        </a>
      </span>
      <button
        phx-click="stop-dev"
        phx-value-id={@worktree_id}
        class="text-red-400 hover:text-red-300 cursor-pointer ml-auto"
      >
        [stop]
      </button>
    </div>
    """
  end

  def preview_indicator(%{dev_server: %{status: :error}} = assigns) do
    ~H"""
    <div class="px-3 py-1 flex items-center gap-2 text-xs">
      <span class="text-red-400">PREVIEW ✕</span>
      <span class="text-red-400/70 truncate">{@dev_server.error || "error"}</span>
      <button
        phx-click="start-dev"
        phx-value-id={@worktree_id}
        class="text-base-content/30 hover:text-cyan-400 cursor-pointer ml-auto"
      >
        [retry]
      </button>
    </div>
    """
  end

  def preview_indicator(assigns) do
    ~H"""
    """
  end

  # --- Task Detail Modal (slide-over drawer) ---

  attr :task, :map, required: true
  attr :children, :list, default: []
  attr :editing_field, :atom, default: nil
  attr :working_agent, :map, default: nil
  attr :agent_output, :list, default: []
  attr :dev_server, :map, default: nil

  def task_detail_drawer(assigns) do
    ~H"""
    <div class="fixed inset-0 z-40" phx-window-keydown="hotkey">
      <%!-- Backdrop --%>
      <div
        class="absolute inset-0 bg-black/50"
        phx-click="deselect-task"
      />

      <%!-- Drawer panel --%>
      <div class="absolute right-0 top-0 bottom-0 w-full sm:max-w-lg bg-base-100 border-l border-base-content/10 overflow-y-auto">
        <%!-- Close button --%>
        <div class="flex items-center justify-between px-3 py-2 border-b border-base-content/10">
          <span class="text-base-content/50 text-xs uppercase tracking-wider font-apothecary">
            {if(String.starts_with?(to_string(@task.id), "wt-"), do: "CONCOCTION", else: "INGREDIENT")} {@task.id}
          </span>
          <button
            phx-click="deselect-task"
            class="text-base-content/30 hover:text-base-content cursor-pointer text-sm"
          >
            [esc]
          </button>
        </div>

        <%!-- Panel content --%>
        <.task_detail_panel
          task={@task}
          children={@children}
          editing_field={@editing_field}
          working_agent={@working_agent}
          agent_output={@agent_output}
          dev_server={@dev_server}
        />
      </div>
    </div>
    """
  end

  # --- Task Detail Panel (reused content) ---

  attr :task, :map, required: true
  attr :children, :list, default: []
  attr :editing_field, :atom, default: nil
  attr :working_agent, :map, default: nil
  attr :agent_output, :list, default: []
  attr :dev_server, :map, default: nil

  def task_detail_panel(assigns) do
    assigns = assign(assigns, :pr_url, Map.get(assigns.task, :pr_url))

    ~H"""
    <div class="space-y-3 p-3">
      <%!-- Status line --%>
      <div class="flex items-center gap-3 flex-wrap">
        <.status_badge status={@task.status} />
        <.priority_badge priority={@task.priority} />
        <span :if={@task.type} class="text-base-content/40">{@task.type}</span>
        <span :if={@task.assigned_to} class="text-cyan-400">{@task.assigned_to}</span>
      </div>

      <%!-- Title (inline editable) --%>
      <%= if @editing_field == :title do %>
        <.form for={%{}} phx-submit="save-edit" class="flex items-center gap-2">
          <input type="hidden" name="field" value="title" />
          <input
            type="text"
            name="value"
            value={@task.title}
            autofocus
            phx-focus="input-focus"
            phx-blur="input-blur"
            class="bg-transparent border-b border-primary outline-none px-1 py-0.5 text-base flex-1"
          />
          <button type="submit" class="text-green-400 hover:text-green-300 text-xs cursor-pointer">
            [save]
          </button>
          <button
            type="button"
            phx-click="cancel-edit"
            class="text-base-content/30 hover:text-base-content/50 text-xs cursor-pointer"
          >
            [esc]
          </button>
        </.form>
      <% else %>
        <div
          phx-click="start-edit"
          phx-value-field="title"
          class="text-base cursor-pointer hover:bg-base-content/5 px-1 -mx-1"
        >
          {@task.title}
        </div>
      <% end %>

      <%!-- Description (inline editable) --%>
      <%= if @editing_field == :description do %>
        <.form for={%{}} phx-submit="save-edit" class="space-y-1">
          <input type="hidden" name="field" value="description" />
          <textarea
            name="value"
            rows="4"
            autofocus
            phx-focus="input-focus"
            phx-blur="input-blur"
            class="bg-transparent border border-primary/30 outline-none px-2 py-1 text-xs w-full"
          >{@task.description || ""}</textarea>
          <div class="flex items-center gap-2">
            <button type="submit" class="text-green-400 hover:text-green-300 text-xs cursor-pointer">
              [save]
            </button>
            <button
              type="button"
              phx-click="cancel-edit"
              class="text-base-content/30 hover:text-base-content/50 text-xs cursor-pointer"
            >
              [esc]
            </button>
          </div>
        </.form>
      <% else %>
        <div
          phx-click="start-edit"
          phx-value-field="description"
          class="text-base-content/60 whitespace-pre-wrap text-xs border-l-2 border-base-content/10 pl-3 cursor-pointer hover:bg-base-content/5 min-h-6"
        >
          {if @task.description && @task.description != "",
            do: @task.description,
            else: "(click to add description)"}
        </div>
      <% end %>

      <%!-- Notes --%>
      <div :if={@task.notes && @task.notes != ""} class="space-y-1">
        <.section label="notes" />
        <div class="text-base-content/50 whitespace-pre-wrap text-xs px-3">{@task.notes}</div>
      </div>

      <%!-- PR info --%>
      <div :if={@pr_url} class="space-y-1">
        <.section label="pull request" />
        <div class="flex items-center gap-2 px-3 text-xs">
          <a href={@pr_url} target="_blank" class="text-purple-400 hover:text-purple-300 truncate">
            {@pr_url}
          </a>
        </div>
      </div>

      <%!-- Actions --%>
      <div class="flex items-center gap-3 text-xs pt-1">
        <button phx-click="claim" class="text-cyan-400 hover:text-cyan-300 cursor-pointer">
          [claim]
        </button>
        <button phx-click="requeue" class="text-yellow-400 hover:text-yellow-300 cursor-pointer">
          [q:requeue]
        </button>
        <button phx-click="close" class="text-red-400 hover:text-red-300 cursor-pointer">
          [x:close]
        </button>
        <button
          :if={@task.status == "pr_open" && @pr_url}
          phx-click="merge-pr"
          class="text-green-400 hover:text-green-300 cursor-pointer font-bold"
        >
          [m:merge]
        </button>
      </div>

      <%!-- Children section --%>
      <div class="space-y-1">
        <.section label="ingredients" />
        <.child_task_row :for={child <- @children} task={child} />
        <div :if={@children == []} class="text-base-content/30 px-4 text-xs">no ingredients</div>
        <.form for={%{}} phx-submit="create-child" class="flex items-center gap-2 px-4 text-xs">
          <input
            type="text"
            name="title"
            id="child-input"
            placeholder="add ingredient..."
            phx-focus="input-focus"
            phx-blur="input-blur"
            autocomplete="off"
            class="bg-transparent border-b border-base-content/20 focus:border-primary outline-none px-1 py-0.5 text-xs flex-1"
          />
          <button type="submit" class="text-green-400 hover:text-green-300 cursor-pointer">
            [enter]
          </button>
        </.form>
      </div>

      <%!-- Blocked by section --%>
      <div class="space-y-1">
        <.section label="blocked by" />
        <div :for={b <- @task.blockers} class="flex items-center gap-2 px-4 text-xs">
          <.link patch={~p"/?task=#{b}"} class="text-red-400 hover:text-red-300">{b}</.link>
          <button
            phx-click="remove-dep"
            phx-value-blocker_id={b}
            class="text-base-content/30 hover:text-red-400 cursor-pointer"
          >
            [x]
          </button>
        </div>
        <div :if={@task.blockers == []} class="text-base-content/30 px-4 text-xs">none</div>
        <.form for={%{}} phx-submit="add-dep" class="flex items-center gap-2 px-4 text-xs">
          <input
            type="text"
            name="dep_id"
            placeholder="add dependency (ID)..."
            phx-focus="input-focus"
            phx-blur="input-blur"
            autocomplete="off"
            class="bg-transparent border-b border-base-content/20 focus:border-primary outline-none px-1 py-0.5 text-xs flex-1"
          />
          <button type="submit" class="text-green-400 hover:text-green-300 cursor-pointer">
            [enter]
          </button>
        </.form>
      </div>

      <%!-- Blocks section --%>
      <div :if={@task.dependents != []} class="space-y-1">
        <.section label="blocks" />
        <div :for={d <- @task.dependents} class="px-4 text-xs">
          <.link patch={~p"/?task=#{d}"} class="text-cyan-400 hover:text-cyan-300">{d}</.link>
        </div>
      </div>

      <%!-- Preview & shortcuts section --%>
      <div :if={String.starts_with?(to_string(@task.id), "wt-")} class="space-y-1">
        <.section label="preview" />
        <.dev_server_detail task_id={@task.id} dev_server={@dev_server} />
        <div class="flex items-center gap-3 px-3 text-xs text-base-content/30">
          <span>
            <span class="text-amber-400">d</span> view diff
          </span>
        </div>
      </div>

      <%!-- Agent output --%>
      <.agent_output_panel
        :if={@working_agent}
        working_agent={@working_agent}
        agent_output={@agent_output}
      />
    </div>
    """
  end

  # --- Section header ---

  attr :label, :string, required: true

  def section(assigns) do
    ~H"""
    <div class="flex items-center gap-2 text-base-content/40 text-xs uppercase tracking-widest select-none">
      <span>──</span>
      <span>{@label}</span>
      <span class="flex-1 border-b border-base-content/10"></span>
    </div>
    """
  end

  # --- Child task row ---

  attr :task, :map, required: true

  def child_task_row(assigns) do
    ~H"""
    <.link
      patch={~p"/?task=#{@task.id}"}
      class="flex items-center gap-2 px-4 py-0.5 hover:bg-base-content/5 cursor-pointer"
    >
      <span class={["w-10 shrink-0 uppercase text-xs", status_color(@task.status)]}>
        {status_abbrev(@task.status)}
      </span>
      <span class="text-base-content/50 shrink-0">{@task.id}</span>
      <span class="truncate">{@task.title}</span>
    </.link>
    """
  end

  # --- Agent output panel ---

  attr :working_agent, :map, required: true
  attr :agent_output, :list, default: []

  def agent_output_panel(assigns) do
    ~H"""
    <div class="space-y-1">
      <.section label={"brewer-#{@working_agent.id} output"} />
      <div
        id="agent-output"
        phx-hook="ScrollBottom"
        class="bg-base-200/50 p-2 text-xs max-h-64 overflow-y-auto"
      >
        <div :for={line <- @agent_output} class="text-base-content/60 whitespace-pre-wrap break-all">
          {line}
        </div>
        <div :if={@agent_output == []} class="text-base-content/30">waiting for output...</div>
      </div>
    </div>
    """
  end

  # --- Preview Detail (in detail panel) ---

  attr :task_id, :string, required: true
  attr :dev_server, :map, default: nil

  defp dev_server_detail(%{dev_server: nil} = assigns) do
    ~H"""
    <div class="flex items-center gap-2 px-3 text-xs">
      <span class="text-base-content/30">not running</span>
      <button
        phx-click="start-dev"
        phx-value-id={@task_id}
        class="text-cyan-400 hover:text-cyan-300 cursor-pointer"
      >
        [D: start preview]
      </button>
    </div>
    """
  end

  defp dev_server_detail(%{dev_server: %{status: :starting}} = assigns) do
    ~H"""
    <div class="px-3 space-y-1">
      <div class="flex items-center gap-2 text-xs">
        <span class="text-cyan-400 animate-pulse">◐ starting...</span>
      </div>
    </div>
    """
  end

  defp dev_server_detail(%{dev_server: %{status: :running}} = assigns) do
    ~H"""
    <div class="px-3 space-y-2">
      <div class="flex items-center gap-2 text-xs flex-wrap">
        <span class="text-green-400">● running</span>
        <button
          phx-click="stop-dev"
          phx-value-id={@task_id}
          class="text-red-400 hover:text-red-300 cursor-pointer"
        >
          [D: stop preview]
        </button>
      </div>
      <div class="flex items-center gap-3 text-xs flex-wrap">
        <span :for={p <- @dev_server.ports}>
          <a
            href={"http://localhost:#{p.port}"}
            target="_blank"
            class="text-cyan-400 hover:text-cyan-300"
          >
            {p.name}:{p.port}
          </a>
        </span>
      </div>
      <div
        :if={@dev_server.output != []}
        class="bg-base-200/50 p-2 text-xs max-h-40 overflow-y-auto"
      >
        <div
          :for={line <- @dev_server.output}
          class="text-base-content/50 whitespace-pre-wrap break-all"
        >
          {line}
        </div>
      </div>
    </div>
    """
  end

  defp dev_server_detail(%{dev_server: %{status: :error}} = assigns) do
    ~H"""
    <div class="px-3 space-y-1">
      <div class="flex items-center gap-2 text-xs">
        <span class="text-red-400">✕ error</span>
        <button
          phx-click="start-dev"
          phx-value-id={@task_id}
          class="text-base-content/30 hover:text-cyan-400 cursor-pointer"
        >
          [retry]
        </button>
      </div>
      <div :if={@dev_server.error} class="text-red-400/70 text-xs">{@dev_server.error}</div>
      <div
        :if={@dev_server.output != []}
        class="bg-base-200/50 p-2 text-xs max-h-40 overflow-y-auto"
      >
        <div
          :for={line <- @dev_server.output}
          class="text-base-content/50 whitespace-pre-wrap break-all"
        >
          {line}
        </div>
      </div>
    </div>
    """
  end

  defp dev_server_detail(assigns) do
    ~H"""
    <div class="flex items-center gap-2 px-3 text-xs">
      <span class="text-base-content/30">not running</span>
      <button
        phx-click="start-dev"
        phx-value-id={@task_id}
        class="text-cyan-400 hover:text-cyan-300 cursor-pointer"
      >
        [D: start preview]
      </button>
    </div>
    """
  end

  # --- Badges ---

  attr :status, :string, default: nil

  def status_badge(assigns) do
    ~H"""
    <span class={["uppercase text-sm", status_color(@status)]}>
      {status_abbrev(@status)}
    </span>
    """
  end

  attr :priority, :any, default: nil

  def priority_badge(assigns) do
    ~H"""
    <span :if={@priority} class={["text-sm", priority_color(@priority)]}>
      P{@priority}
    </span>
    """
  end

  # --- Diff overlay (lazygit-style) ---

  attr :diff_view, :map, required: true

  def diff_overlay(assigns) do
    diff = assigns.diff_view

    current_file =
      if diff.files != [] do
        Enum.at(diff.files, diff.selected_file)
      end

    assigns =
      assigns
      |> assign(:current_file, current_file)
      |> assign(:diff, diff)

    ~H"""
    <div class="fixed inset-0 z-50 flex flex-col bg-base-100">
      <%!-- Header bar --%>
      <div class="flex items-center justify-between px-4 py-2 border-b border-base-content/10 bg-base-200/50 shrink-0">
        <div class="flex items-center gap-3">
          <span class="text-cyan-400 font-bold text-sm uppercase tracking-wider">DIFF</span>
          <span class="text-base-content/50 text-sm">{@diff.worktree_id}</span>
          <span :if={@diff.loading} class="text-yellow-400 text-xs animate-pulse">loading...</span>
        </div>
        <span class="text-base-content/30 text-xs">[esc] close  j/k navigate files</span>
      </div>

      <%!-- Error state --%>
      <div :if={@diff.error && !@diff.loading} class="flex-1 flex items-center justify-center">
        <div class="text-center space-y-2">
          <div class="text-red-400 text-sm">{@diff.error}</div>
          <div class="text-base-content/30 text-xs">press esc to close</div>
        </div>
      </div>

      <%!-- Loading state --%>
      <div :if={@diff.loading} class="flex-1 flex items-center justify-center">
        <div class="text-yellow-400 text-sm animate-pulse">Fetching diff...</div>
      </div>

      <%!-- Main split pane --%>
      <div
        :if={!@diff.loading && !@diff.error && @diff.files != []}
        class="flex flex-1 overflow-hidden"
      >
        <%!-- Left pane: file list --%>
        <div
          id="diff-file-list"
          class="w-64 shrink-0 border-r border-base-content/10 overflow-y-auto bg-base-200/30"
        >
          <div class="px-2 py-1 text-xs text-base-content/30 uppercase tracking-wider border-b border-base-content/5">
            Files ({length(@diff.files)})
          </div>
          <div
            :for={{file, idx} <- Enum.with_index(@diff.files)}
            data-diff-selected={if(idx == @diff.selected_file, do: "true")}
            class={[
              "px-3 py-1 text-xs truncate cursor-default",
              if(idx == @diff.selected_file,
                do: "bg-primary/20 text-primary border-l-2 border-primary",
                else: "text-base-content/60 hover:bg-base-content/5 border-l-2 border-transparent"
              )
            ]}
          >
            <span class={diff_file_color(file.lines)}>{file.path}</span>
          </div>
        </div>

        <%!-- Right pane: diff content --%>
        <div class="flex-1 overflow-y-auto" id="diff-content-pane">
          <div :if={@current_file} class="font-mono text-xs">
            <div class="sticky top-0 px-4 py-1 bg-base-200 border-b border-base-content/10 text-base-content/50">
              {@current_file.path}
            </div>
            <div
              :for={line <- @current_file.lines}
              class={[
                "px-4 whitespace-pre",
                diff_line_class(line.type)
              ]}
            >
              {line.text}
            </div>
          </div>
        </div>
      </div>

      <%!-- Empty diff state --%>
      <div
        :if={!@diff.loading && !@diff.error && @diff.files == []}
        class="flex-1 flex items-center justify-center"
      >
        <div class="text-base-content/30 text-sm">No changes found</div>
      </div>
    </div>
    """
  end

  defp diff_line_class(:add), do: "bg-green-900/30 text-green-300"
  defp diff_line_class(:del), do: "bg-red-900/30 text-red-300"
  defp diff_line_class(:hunk), do: "bg-cyan-900/20 text-cyan-400"
  defp diff_line_class(:ctx), do: "text-base-content/50"
  defp diff_line_class(_), do: "text-base-content/50"

  defp diff_file_color(lines) do
    has_add = Enum.any?(lines, &(&1.type == :add))
    has_del = Enum.any?(lines, &(&1.type == :del))

    cond do
      has_add and has_del -> "text-yellow-400"
      has_add -> "text-green-400"
      has_del -> "text-red-400"
      true -> "text-base-content/60"
    end
  end

  # --- Which-key help overlay ---

  attr :page, :atom, default: :dashboard
  attr :has_selected_task, :boolean, default: false

  def which_key_overlay(assigns) do
    ~H"""
    <div
      class="fixed inset-0 z-50 flex items-center justify-center bg-black/70"
      phx-click="close-help"
    >
      <div
        class="bg-base-300 border border-base-content/20 p-4 max-w-xl w-full mx-4 max-h-[80vh] overflow-y-auto rounded-xl"
        phx-click={%Phoenix.LiveView.JS{}}
      >
        <div class="flex items-center justify-between mb-3 text-sm">
          <span class="text-base-content/50 uppercase tracking-wider font-apothecary">
            ── keybindings ──
          </span>
          <span class="text-base-content/30">[esc] close</span>
        </div>

        <div class="grid grid-cols-1 md:grid-cols-2 gap-4 text-sm">
          <div class="space-y-1">
            <div class="text-emerald-400 mb-1">navigation</div>
            <.hk key="j/k" desc="next/prev concoction" />
            <.hk key="g/G" desc="first/last concoction" />
            <.hk key="enter/l" desc="inspect concoction" />
            <.hk key="esc/h" desc="close / back" />
            <.hk key="/ or c" desc="focus input" />
          </div>

          <div class="space-y-1">
            <div class="text-emerald-400 mb-1">lanes</div>
            <.hk key="1" desc="jump to stockroom" />
            <.hk key="2" desc="jump to brewing" />
            <.hk key="3" desc="jump to assaying" />
            <.hk key="4" desc="jump to bottled" />
          </div>

          <div class="space-y-1">
            <div class="text-emerald-400 mb-1">actions</div>
            <.hk key="s" desc="start/stop swarm" />
            <.hk key="+/-" desc="brewer count" />
            <.hk key="r" desc="refresh" />
            <.hk key="R" desc="requeue orphans" />
            <.hk key="d" desc="view diff" />
            <.hk key="D" desc="toggle preview" />
            <.hk key="?" desc="toggle this help" />
          </div>

          <div :if={@has_selected_task} class="space-y-1">
            <div class="text-emerald-400 mb-1">when inspecting</div>
            <.hk key="q" desc="requeue concoction" />
            <.hk key="x" desc="close concoction" />
            <.hk key="m" desc="merge PR (pr_open)" />
          </div>
        </div>
      </div>
    </div>
    """
  end

  defp hk(assigns) do
    ~H"""
    <div class="flex items-center justify-between gap-3">
      <span class="text-base-content/50">{@desc}</span>
      <span class="text-amber-400">{@key}</span>
    </div>
    """
  end

  # --- Agent status badge (used by AgentLive) ---

  attr :status, :atom, default: :idle

  def agent_status_badge(assigns) do
    ~H"""
    <span class={agent_status_color(@status)}>
      {Atom.to_string(@status)}
    </span>
    """
  end

  defp agent_status_color(:working), do: "text-green-400"
  defp agent_status_color(:idle), do: "text-yellow-400"
  defp agent_status_color(:starting), do: "text-cyan-400"
  defp agent_status_color(:error), do: "text-red-400"
  defp agent_status_color(_), do: "text-base-content/30"

  # --- Status bar (used by AgentLive) ---

  attr :page, :atom, default: :dashboard
  attr :swarm_status, :atom, default: :paused
  attr :agent_count, :integer, default: 0
  attr :orphan_count, :integer, default: 0

  def status_bar(assigns) do
    ~H"""
    <div class="fixed bottom-0 left-0 right-0 z-40 bg-base-300 border-t border-base-content/10 px-3 py-1 flex items-center justify-between text-xs">
      <div class="flex items-center gap-3">
        <span class="text-base-content/30">-- {page_label(@page)} --</span>
      </div>
      <div class="flex items-center gap-3 text-base-content/30">
        <span>?:help</span>
        <span>bksp:back</span>
      </div>
    </div>
    """
  end

  defp page_label(:dashboard), do: "NORMAL"
  defp page_label(:agent), do: "BREWER"
  defp page_label(_), do: ""

  # --- Helper functions ---

  defp status_abbrev("open"), do: "RDY"
  defp status_abbrev("ready"), do: "RDY"
  defp status_abbrev("in_progress"), do: "WIP"
  defp status_abbrev("claimed"), do: "WIP"
  defp status_abbrev("pr_open"), do: "PR"
  defp status_abbrev("revision_needed"), do: "REV"
  defp status_abbrev("merged"), do: "MRG"
  defp status_abbrev("done"), do: "DONE"
  defp status_abbrev("closed"), do: "DONE"
  defp status_abbrev("blocked"), do: "BLK"
  defp status_abbrev(nil), do: "???"
  defp status_abbrev(_), do: "???"

  defp status_color("open"), do: "text-emerald-400"
  defp status_color("ready"), do: "text-emerald-400"
  defp status_color("in_progress"), do: "text-amber-400"
  defp status_color("claimed"), do: "text-amber-400"
  defp status_color("pr_open"), do: "text-purple-400"
  defp status_color("revision_needed"), do: "text-orange-400"
  defp status_color("merged"), do: "text-green-400"
  defp status_color("done"), do: "text-green-400/70"
  defp status_color("closed"), do: "text-green-400/70"
  defp status_color("blocked"), do: "text-red-400"
  defp status_color(_), do: "text-base-content/30"

  defp priority_color(0), do: "text-red-400"
  defp priority_color(1), do: "text-yellow-400"
  defp priority_color(2), do: "text-base-content/50"
  defp priority_color(3), do: "text-cyan-400"
  defp priority_color(_), do: "text-base-content/30"

  defp agent_dot(:working), do: "●"
  defp agent_dot(:idle), do: "○"
  defp agent_dot(:starting), do: "◐"
  defp agent_dot(:error), do: "✕"
  defp agent_dot(_), do: "·"

  defp agent_dot_color(:working), do: "text-green-400"
  defp agent_dot_color(:idle), do: "text-yellow-400"
  defp agent_dot_color(:starting), do: "text-cyan-400"
  defp agent_dot_color(:error), do: "text-red-400"
  defp agent_dot_color(_), do: "text-base-content/30"

  defp group_badge_classes("running"), do: "bg-amber-400/15 text-amber-400"
  defp group_badge_classes("ready"), do: "bg-emerald-400/15 text-emerald-400"
  defp group_badge_classes("blocked"), do: "bg-red-400/15 text-red-400/80"
  defp group_badge_classes("pr"), do: "bg-purple-400/15 text-purple-400"
  defp group_badge_classes("done"), do: "bg-green-400/10 text-green-400/60"
  defp group_badge_classes(_), do: ""

  defp group_badge_label("running"), do: "BREWING"
  defp group_badge_label("ready"), do: "STOCKED"
  defp group_badge_label("blocked"), do: "MISSING"
  defp group_badge_label("pr"), do: "ASSAYING"
  defp group_badge_label("done"), do: "BOTTLED"
  defp group_badge_label(_), do: ""

  # --- Tab Navigation ---

  attr :active_tab, :atom, required: true

  def tab_navigation(assigns) do
    ~H"""
    <div class="flex items-center gap-1 px-2 py-1">
      <button
        phx-click="switch-tab"
        phx-value-tab="stockroom"
        class={[
          "px-3 py-1.5 text-xs font-apothecary tracking-wide rounded transition-colors cursor-pointer",
          if(@active_tab == :stockroom,
            do: "text-base-content bg-base-content/10 font-bold",
            else: "text-base-content/40 hover:text-base-content/70 hover:bg-base-content/5"
          )
        ]}
      >
        Stockroom
      </button>
      <button
        phx-click="switch-tab"
        phx-value-tab="recipes"
        class={[
          "px-3 py-1.5 text-xs font-apothecary tracking-wide rounded transition-colors cursor-pointer",
          if(@active_tab == :recipes,
            do: "text-base-content bg-base-content/10 font-bold",
            else: "text-base-content/40 hover:text-base-content/70 hover:bg-base-content/5"
          )
        ]}
      >
        Recurring Brews
      </button>
    </div>
    """
  end

  # --- Recipe List ---

  attr :recipes, :list, required: true
  attr :show_recipe_form, :boolean, default: false
  attr :recipe_form, :any, default: nil
  attr :editing_recipe_id, :string, default: nil

  def recipe_list(assigns) do
    ~H"""
    <div class="max-w-3xl mx-auto pt-8 pb-4">
      <div class="flex items-center justify-between mb-6">
        <div>
          <h2 class="text-base-content/50 text-lg font-semibold font-apothecary">
            Recurring Brews
          </h2>
          <p class="text-base-content/30 text-xs mt-1">
            Recipes that automatically create concoctions on a schedule
          </p>
        </div>
        <button
          :if={!@show_recipe_form}
          phx-click="show-recipe-form"
          class="flex items-center gap-1.5 border border-base-content/20 hover:border-base-content/40 text-base-content/60 hover:text-base-content px-3 py-1.5 rounded text-xs cursor-pointer transition-colors"
        >
          <span>+</span>
          <span>New Recipe</span>
        </button>
      </div>

      <.recipe_form :if={@show_recipe_form} form={@recipe_form} editing_id={@editing_recipe_id} />

      <%= if @recipes == [] and !@show_recipe_form do %>
        <div class="text-center py-16">
          <div class="text-4xl mb-3 opacity-20">&#x1F4DC;</div>
          <p class="text-base-content/30 text-sm">No recipes yet</p>
          <p class="text-base-content/20 text-xs mt-1">
            Create a recipe to schedule recurring brews
          </p>
        </div>
      <% else %>
        <div class="space-y-2">
          <.recipe_card :for={recipe <- @recipes} recipe={recipe} />
        </div>
      <% end %>
    </div>
    """
  end

  # --- Recipe Form ---

  attr :form, :any, required: true
  attr :editing_id, :string, default: nil

  def recipe_form(assigns) do
    ~H"""
    <div class="border border-base-content/15 rounded-lg p-4 mb-4 bg-base-content/3">
      <div class="flex items-center justify-between mb-3">
        <h3 class="text-sm font-semibold text-base-content/70 font-apothecary">
          {if(@editing_id, do: "Edit Recipe", else: "New Recipe")}
        </h3>
        <button
          phx-click="cancel-recipe-form"
          class="text-base-content/30 hover:text-base-content/60 text-xs cursor-pointer"
        >
          Cancel
        </button>
      </div>

      <.form for={@form} id="recipe-form" phx-submit="save-recipe">
        <input type="hidden" name="recipe[id]" value={@editing_id} />
        <div class="space-y-3">
          <div>
            <label class="text-xs text-base-content/40 block mb-1">Title</label>
            <input
              type="text"
              name="recipe[title]"
              value={@form[:title].value}
              placeholder="e.g. Daily dependency updates"
              class="bg-transparent border border-base-content/20 focus:border-primary outline-none px-3 py-1.5 text-sm w-full rounded"
              required
            />
          </div>

          <div>
            <label class="text-xs text-base-content/40 block mb-1">Description</label>
            <textarea
              name="recipe[description]"
              rows="3"
              placeholder="The task description that will be used when creating the concoction..."
              class="bg-transparent border border-base-content/20 focus:border-primary outline-none px-3 py-1.5 text-sm w-full rounded resize-none"
            >{@form[:description].value}</textarea>
          </div>

          <div class="grid grid-cols-2 gap-3">
            <div>
              <label class="text-xs text-base-content/40 block mb-1">
                Schedule (cron expression)
              </label>
              <input
                type="text"
                name="recipe[schedule]"
                value={@form[:schedule].value}
                placeholder="0 9 * * MON-FRI"
                class="bg-transparent border border-base-content/20 focus:border-primary outline-none px-3 py-1.5 text-sm w-full rounded font-mono"
                required
              />
              <p class="text-[10px] text-base-content/25 mt-1">
                min hour day month weekday (UTC)
              </p>
            </div>

            <div>
              <label class="text-xs text-base-content/40 block mb-1">Priority</label>
              <select
                name="recipe[priority]"
                class="bg-transparent border border-base-content/20 focus:border-primary outline-none px-3 py-1.5 text-sm w-full rounded"
              >
                <option value="0" selected={@form[:priority].value == "0"}>P0 - Critical</option>
                <option value="1" selected={@form[:priority].value == "1"}>P1 - High</option>
                <option value="2" selected={@form[:priority].value == "2"}>P2 - Medium</option>
                <option
                  value="3"
                  selected={@form[:priority].value in [nil, "", "3"]}
                >
                  P3 - Default
                </option>
                <option value="4" selected={@form[:priority].value == "4"}>P4 - Backlog</option>
              </select>
            </div>
          </div>

          <div class="flex justify-end pt-1">
            <button
              type="submit"
              class="bg-primary/20 hover:bg-primary/30 text-primary px-4 py-1.5 rounded text-xs cursor-pointer transition-colors"
            >
              {if(@editing_id, do: "Update Recipe", else: "Create Recipe")}
            </button>
          </div>
        </div>
      </.form>
    </div>
    """
  end

  # --- Recipe Card ---

  attr :recipe, :any, required: true

  def recipe_card(assigns) do
    ~H"""
    <div class={[
      "border rounded-lg px-4 py-3 transition-colors",
      if(@recipe.enabled,
        do: "border-base-content/15 bg-base-content/3",
        else: "border-base-content/8 bg-base-content/2 opacity-60"
      )
    ]}>
      <div class="flex items-start justify-between gap-3">
        <div class="flex-1 min-w-0">
          <div class="flex items-center gap-2">
            <h3 class="text-sm font-medium text-base-content/80 truncate">
              {@recipe.title}
            </h3>
            <span class={[
              "text-[10px] px-1.5 py-0.5 rounded",
              priority_color(@recipe.priority)
            ]}>
              P{@recipe.priority || 3}
            </span>
            <span class={[
              "text-[10px] px-1.5 py-0.5 rounded",
              if(@recipe.enabled,
                do: "bg-emerald-400/15 text-emerald-400",
                else: "bg-base-content/10 text-base-content/30"
              )
            ]}>
              {if(@recipe.enabled, do: "active", else: "paused")}
            </span>
          </div>

          <p :if={@recipe.description} class="text-xs text-base-content/30 mt-1 line-clamp-2">
            {@recipe.description}
          </p>

          <div class="flex items-center gap-4 mt-2 text-[11px] text-base-content/30">
            <span class="font-mono bg-base-content/5 px-1.5 py-0.5 rounded text-base-content/50">
              {@recipe.schedule}
            </span>
            <span :if={@recipe.next_run_at} class="flex items-center gap-1">
              <span class="text-base-content/20">next:</span>
              {format_relative_time(@recipe.next_run_at)}
            </span>
            <span :if={@recipe.last_run_at} class="flex items-center gap-1">
              <span class="text-base-content/20">last:</span>
              {format_relative_time(@recipe.last_run_at)}
            </span>
          </div>
        </div>

        <div class="flex items-center gap-1 shrink-0">
          <button
            phx-click="toggle-recipe"
            phx-value-id={@recipe.id}
            class="text-base-content/30 hover:text-base-content/60 px-2 py-1 text-xs cursor-pointer transition-colors"
            title={if(@recipe.enabled, do: "Pause", else: "Resume")}
          >
            {if(@recipe.enabled, do: "pause", else: "resume")}
          </button>
          <button
            phx-click="edit-recipe"
            phx-value-id={@recipe.id}
            class="text-base-content/30 hover:text-base-content/60 px-2 py-1 text-xs cursor-pointer transition-colors"
            title="Edit"
          >
            edit
          </button>
          <button
            phx-click="delete-recipe"
            phx-value-id={@recipe.id}
            class="text-base-content/30 hover:text-red-400/60 px-2 py-1 text-xs cursor-pointer transition-colors"
            title="Delete"
            data-confirm="Delete this recipe?"
          >
            delete
          </button>
        </div>
      </div>
    </div>
    """
  end

  defp format_relative_time(nil), do: "—"

  defp format_relative_time(iso_string) when is_binary(iso_string) do
    case DateTime.from_iso8601(iso_string) do
      {:ok, dt, _} ->
        now = DateTime.utc_now()
        diff = DateTime.diff(dt, now, :second)

        cond do
          diff > 86_400 -> "#{div(diff, 86_400)}d"
          diff > 3_600 -> "#{div(diff, 3_600)}h"
          diff > 60 -> "#{div(diff, 60)}m"
          diff > 0 -> "#{diff}s"
          diff > -60 -> "just now"
          diff > -3_600 -> "#{div(-diff, 60)}m ago"
          diff > -86_400 -> "#{div(-diff, 3_600)}h ago"
          true -> "#{div(-diff, 86_400)}d ago"
        end

      _ ->
        iso_string
    end
  end
end
