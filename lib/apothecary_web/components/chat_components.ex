defmodule ApothecaryWeb.ChatComponents do
  @moduledoc "HEEx components for the chat UI."
  use Phoenix.Component
  import ApothecaryWeb.DashboardComponents, only: [braille_spinner: 1]

  alias ApothecaryWeb.ChatLive.Context

  # ── Message dispatcher ──────────────────────────────────

  attr :msg, :any, required: true

  def chat_message(assigns) do
    ~H"""
    <div class={"chat-msg chat-msg-#{@msg.type}"} id={"msg-#{@msg.id}"}>
      <%= case @msg.type do %>
        <% :user -> %>
          <.user_message msg={@msg} />
        <% :system -> %>
          <.system_message msg={@msg} />
        <% :brewer_event -> %>
          <.brewer_event msg={@msg} />
        <% :oracle_response -> %>
          <.oracle_message msg={@msg} />
        <% :status -> %>
          <.status_message msg={@msg} />
        <% :error -> %>
          <.error_message msg={@msg} />
        <% _ -> %>
          <.system_message msg={@msg} />
      <% end %>
    </div>
    """
  end

  # ── User message ────────────────────────────────────────
  # Shows: "you 2:42" then "wb · /s" on next line

  attr :msg, :any, required: true

  defp user_message(assigns) do
    ~H"""
    <div class="chat-user-header">
      <span style="color: var(--dim);">you</span>
      <span class="chat-timestamp"><%= format_time(@msg.timestamp) %></span>
    </div>
    <div class="chat-user-body">
      <%= if @msg.context_label != "" do %>
        <span style="color: var(--accent);"><%= @msg.context_label %></span>
        <span style="color: var(--dim);"> · </span>
      <% end %>
      <span style="color: var(--text); font-weight: 500;"><%= @msg.body %></span>
    </div>
    """
  end

  # ── System message ──────────────────────────────────────

  attr :msg, :any, required: true

  defp system_message(assigns) do
    ~H"""
    <div class="chat-system-block">
      <div class="chat-system-label">apothecary</div>
      <div class="chat-system-body"><pre class="chat-pre"><%= @msg.body %></pre></div>
    </div>
    """
  end

  # ── Brewer event ────────────────────────────────────────
  # Shows: "— ● ff55d7 task completed · title · +22 -8    2:39"

  attr :msg, :any, required: true

  defp brewer_event(assigns) do
    ~H"""
    <div class="chat-event-line">
      <span style="color: var(--muted);">—</span>
      <span style="color: var(--dim);"><%= @msg.body %></span>
      <span class="chat-timestamp"><%= format_time(@msg.timestamp) %></span>
    </div>
    """
  end

  # ── Oracle message ──────────────────────────────────────

  attr :msg, :any, required: true

  defp oracle_message(assigns) do
    ~H"""
    <div class="chat-system-block">
      <div class="chat-system-label" style="color: var(--accent);">oracle</div>
      <div class="chat-system-body oracle-body"><pre class="chat-pre"><%= @msg.body %></pre></div>
    </div>
    """
  end

  # ── Status message (tree output) ────────────────────────

  attr :msg, :any, required: true

  defp status_message(assigns) do
    ~H"""
    <div class="chat-status-block"><pre class="chat-pre"><%= @msg.body %></pre></div>
    """
  end

  # ── Error message ───────────────────────────────────────

  attr :msg, :any, required: true

  defp error_message(assigns) do
    ~H"""
    <div class="chat-event-line">
      <span style="color: var(--muted);">—</span>
      <span style="color: var(--error);"><%= @msg.body %></span>
    </div>
    """
  end

  # ── Welcome screen ─────────────────────────────────────

  attr :has_project, :boolean, default: false

  def chat_welcome(assigns) do
    ~H"""
    <div class="chat-welcome">
      <div class="chat-welcome-title">What shall we concoct?</div>
      <div class="chat-welcome-hints">
        <%= if @has_project do %>
          <div class="chat-welcome-hint">type a task to create a worktree</div>
          <div class="chat-welcome-hint"><span class="chat-welcome-cmd">status</span> overview of all worktrees</div>
          <div class="chat-welcome-hint"><span class="chat-welcome-cmd">oracle</span> ask a question</div>
          <div class="chat-welcome-hint"><span class="chat-welcome-cmd">start</span> begin brewing</div>
          <div class="chat-welcome-hint"><span class="chat-welcome-cmd">help</span> all commands</div>
        <% else %>
          <div class="chat-welcome-hint">select a project to get started</div>
          <div class="chat-welcome-hint"><span class="chat-welcome-cmd">p name</span> switch to a project</div>
          <div class="chat-welcome-hint"><span class="chat-welcome-cmd">add ~/path</span> add existing project</div>
          <div class="chat-welcome-hint"><span class="chat-welcome-cmd">new ~/path</span> create new project</div>
        <% end %>
      </div>
    </div>
    """
  end

  # ── Input bar ───────────────────────────────────────────

  attr :context, :any, required: true
  attr :context_stack, :list, default: []
  attr :input_value, :string, default: ""
  attr :path_suggestions, :list, default: []
  attr :path_suggestion_selected, :integer, default: 0
  attr :current_project, :any, default: nil

  def chat_input(assigns) do
    project_name = if assigns.current_project, do: assigns.current_project.name, else: nil

    {prompt, placeholder} =
      if project_name do
        ctx_label = Context.label(assigns.context)
        {"#{project_name} · #{ctx_label}", Context.prompt_text(assigns.context)}
      else
        {"apothecary", "p <name> to switch project, add ~/path to add one"}
      end

    assigns = assign(assigns, :ctx_label, prompt)
    assigns = assign(assigns, :placeholder, placeholder)

    ~H"""
    <div class="chat-input-bar">
      <%= if @path_suggestions != [] do %>
        <div class="chat-path-dropdown">
          <button
            :for={{s, idx} <- Enum.with_index(@path_suggestions)}
            type="button"
            phx-click="select-path"
            phx-value-path={s.path}
            class={"chat-path-item #{if idx == @path_suggestion_selected, do: "chat-path-item--selected", else: ""}"}
          >
            <%= if s.is_git do %>
              <span style="color: var(--accent);">●</span>
            <% else %>
              <span style="color: var(--muted);">○</span>
            <% end %>
            <span style="color: var(--text);"><%= s.name %></span>
            <span class="chat-path-dir"><%= Path.dirname(s.path) %>/</span>
          </button>
        </div>
      <% end %>
      <form phx-submit="submit" id="chat-form" class="chat-input-form">
        <span class="chat-input-prompt"><%= @ctx_label %></span>
        <textarea
          id="chat-input"
          name="text"
          phx-hook="ChatInput"
          placeholder={@placeholder}
          rows="1"
          autocomplete="off"
          spellcheck="false"
        ><%= @input_value %></textarea>
      </form>
    </div>
    """
  end

  # ── Top Bar ─────────────────────────────────────────────
  # Left: "apothecary / my-saas"  Right: "⠋ 2 brewing  ◎ 1  ○ 2"

  attr :current_project, :any, default: nil
  attr :projects, :list, default: []
  attr :show_project_switcher, :boolean, default: false
  attr :switcher_selected, :integer, default: 0
  attr :switcher_query, :string, default: ""
  attr :worktrees_state, :map, default: %{}
  attr :agents, :list, default: []

  def chat_top_bar(assigns) do
    # Compute status counts
    items = assigns.worktrees_state[:tasks] || []
    worktrees = Enum.filter(items, &(&1.type == "worktree" && &1.status not in ["merged", "cancelled"]))

    brewing =
      assigns.agents
      |> Enum.count(&(&1.status == :working))

    reviewing = Enum.count(worktrees, &(&1.status == "pr_open"))

    queued =
      Enum.count(worktrees, fn wt ->
        wt.status in ["open", "claimed"] && is_nil(wt.assigned_brewer_id)
      end)

    assigns =
      assigns
      |> assign(:brewing_count, brewing)
      |> assign(:reviewing_count, reviewing)
      |> assign(:queued_count, queued)

    ~H"""
    <div class="chat-top-bar">
      <div class="flex items-center gap-0" style="font-size: var(--font-size-sm);">
        <span style="color: var(--accent);">apothecary</span>
        <%= if @current_project do %>
          <span style="color: var(--dim);"> / </span>
          <button
            phx-click="toggle-project-switcher"
            type="button"
            class="cursor-pointer"
            style={"color: var(--dim); #{if @show_project_switcher, do: "text-decoration: underline; text-decoration-color: var(--accent);", else: ""}"}
          >
            <%= @current_project.name %>
          </button>
        <% else %>
          <button phx-click="toggle-project-switcher" type="button" class="cursor-pointer" style="color: var(--muted);">
            <span style="color: var(--dim);"> / </span>select project
          </button>
        <% end %>
      </div>
      <div class="flex items-center gap-4" style="font-size: var(--font-size-sm);">
        <%= if @brewing_count > 0 do %>
          <span>
            <.braille_spinner id="topbar-spinner" offset={0} />
            <span style="color: var(--concocting);"> <%= @brewing_count %> brewing</span>
          </span>
        <% end %>
        <%= if @reviewing_count > 0 do %>
          <span>
            <span style="color: var(--assaying);">◎ <%= @reviewing_count %></span>
          </span>
        <% end %>
        <%= if @queued_count > 0 do %>
          <span>
            <span style="color: var(--muted);">○ <%= @queued_count %></span>
          </span>
        <% end %>
      </div>
    </div>
    <%= if @show_project_switcher do %>
      <.project_dropdown
        projects={@projects}
        current_project={@current_project}
        selected={@switcher_selected}
        query={@switcher_query}
      />
    <% end %>
    """
  end

  attr :projects, :list, required: true
  attr :current_project, :any, default: nil
  attr :selected, :integer, default: 0
  attr :query, :string, default: ""

  defp project_dropdown(assigns) do
    filtered =
      if assigns.query == "" do
        assigns.projects
      else
        q = String.downcase(assigns.query)
        Enum.filter(assigns.projects, fn p -> String.contains?(String.downcase(p.name), q) end)
      end

    assigns = assign(assigns, :filtered, filtered)

    ~H"""
    <div class="switcher-backdrop" phx-click="toggle-project-switcher">
      <div class="switcher-dropdown" phx-click-away="toggle-project-switcher">
        <div style="padding: 12px;">
          <input
            type="text"
            class="switcher-input"
            placeholder="search projects..."
            phx-keyup="switcher-search"
            value={@query}
            id="chat-switcher-input"
            phx-hook="ChatSwitcherFocus"
            autocomplete="off"
          />
        </div>
        <div class="switcher-list">
          <%= for {project, idx} <- Enum.with_index(@filtered) do %>
            <button
              phx-click="select-project"
              phx-value-id={project.id}
              class={"switcher-item #{if idx == @selected, do: "switcher-item--selected", else: ""}"}
              type="button"
            >
              <div class={"switcher-item-name #{if idx == @selected, do: "switcher-item-name--selected", else: ""}"}>
                <%= project.name %>
              </div>
              <div class="switcher-item-meta">
                <%= project.path %>
                <%= if @current_project && @current_project.id == project.id do %>
                  <span class="switcher-current-badge">current</span>
                <% end %>
              </div>
            </button>
          <% end %>
        </div>
      </div>
    </div>
    """
  end

  # ── Helpers ─────────────────────────────────────────────

  defp format_time(nil), do: ""

  defp format_time(%DateTime{} = dt) do
    Calendar.strftime(dt, "%H:%M")
  end
end
