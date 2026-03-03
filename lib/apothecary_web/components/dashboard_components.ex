defmodule ApothecaryWeb.DashboardComponents do
  @moduledoc "Moonlight-themed function components for the Apothecary dashboard."
  use Phoenix.Component
  # icon/1 is available via html_helpers but we don't currently use it directly

  use Phoenix.VerifiedRoutes,
    endpoint: ApothecaryWeb.Endpoint,
    router: ApothecaryWeb.Router,
    statics: ApothecaryWeb.static_paths()

  # ── Spinner ──────────────────────────────────────────────

  attr :class, :string, default: "w-4 h-4"

  def spinner(assigns) do
    ~H"""
    <svg class={["animate-spin", @class]} style="color: var(--dim);" xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24">
      <circle class="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" stroke-width="4" />
      <path class="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4zm2 5.291A7.962 7.962 0 014 12H0c0 3.042 1.135 5.824 3 7.938l3-2.647z" />
    </svg>
    """
  end

  # ── Copy Button ──────────────────────────────────────────

  attr :target, :string, required: true
  attr :class, :string, default: ""

  def copy_button(assigns) do
    ~H"""
    <button
      id={"copy-btn-" <> String.replace(@target, ~r/[^a-zA-Z0-9]/, "")}
      phx-hook=".CopyText"
      data-copy-target={@target}
      class={["cursor-pointer", @class]}
      style="color: var(--muted); font-size: var(--font-size-xs);"
      title="Copy to clipboard"
    >
      [copy]
    </button>
    <script :type={Phoenix.LiveView.ColocatedHook} name=".CopyText">
      export default {
        mounted() {
          this.el.addEventListener("click", (e) => {
            e.stopPropagation()
            const target = document.querySelector(this.el.dataset.copyTarget)
            if (!target) return
            const text = target.innerText || target.textContent
            navigator.clipboard.writeText(text).then(() => {
              const original = this.el.textContent
              this.el.textContent = "[copied!]"
              this.el.style.color = "var(--accent)"
              setTimeout(() => {
                this.el.textContent = original
                this.el.style.color = "var(--muted)"
              }, 1500)
            })
          })
        }
      }
    </script>
    """
  end

  # ── Top Bar ──────────────────────────────────────────────

  attr :current_project, :any, default: nil
  attr :active_tab, :atom, default: :workbench
  attr :selected_task_id, :string, default: nil
  attr :selected_task, :any, default: nil
  attr :projects, :list, default: []
  attr :show_project_switcher, :boolean, default: false
  attr :worktrees_by_status, :map, default: %{}

  def top_bar(assigns) do
    ~H"""
    <div class="flex items-center justify-between px-4 py-3" style={"font-size: var(--font-size-sm); #{if @show_project_switcher, do: "background: var(--surface);", else: ""}"}>
      <div class="flex items-center gap-0 min-w-0">
        <%= if is_nil(@current_project) do %>
          <span style="color: var(--accent);">apothecary</span>
        <% else %>
          <span style="color: var(--accent);">apothecary</span>
          <span style="color: var(--dim);">&nbsp;/ </span>
          <button
            phx-click="toggle-project-switcher"
            type="button"
            class="cursor-pointer"
            style={"color: var(--dim); #{if @show_project_switcher, do: "text-decoration: underline; text-decoration-color: var(--accent);", else: ""}"}
          >
            {@current_project.name}
          </button>
        <% end %>
      </div>
      <%= cond do %>
        <% @show_project_switcher -> %>
          <span style="color: var(--muted); font-size: var(--font-size-xs);">esc cancel</span>

        <% @current_project -> %>
          <div class="flex items-center gap-3">
            <button
              :for={{tab, label} <- [workbench: "workbench", oracle: "oracle", recipes: "recurring"]}
              phx-click="switch-tab"
              phx-value-tab={tab}
              class="cursor-pointer"
              style={"color: #{if @active_tab == tab, do: "var(--text)", else: "var(--muted)"}; font-size: var(--font-size-sm);"}
            >
              {label}
            </button>
          </div>

        <% true -> %>
      <% end %>
    </div>
    """
  end

  # ── Project Landing ──────────────────────────────────────

  attr :projects, :list, default: []
  attr :project_path_suggestions, :list, default: []
  attr :add_project_error, :string, default: nil
  attr :selected_project, :integer, default: 0

  def project_landing(assigns) do
    ~H"""
    <div class="px-6 py-10 flex flex-col items-center">
      <%!-- Centered header --%>
      <div class="mb-8" style="color: var(--dim); font-size: 14px; letter-spacing: 0.08em; text-transform: uppercase;">
        NO PROJECT OPEN
      </div>

      <%!-- Path input — full width within the column --%>
      <div class="w-full max-w-[480px]">
        <form phx-submit="add-project" phx-change="search-project-path" class="relative">
          <input
            type="text"
            name="path"
            value={System.get_env("HOME", "~") <> "/"}
            autofocus
            autocomplete="off"
            phx-debounce="150"
            class="moonlight-input w-full"
            style="caret-color: var(--accent); padding: 16px 20px; font-size: 14px;"
          />
          <div
            :if={@project_path_suggestions != []}
            class="absolute left-0 right-0 top-full mt-1 max-h-48 overflow-y-auto z-50"
            style="background: var(--surface); border: 1px solid var(--border);"
          >
            <button
              :for={s <- @project_path_suggestions}
              type="button"
              phx-click="select-project-path"
              phx-value-path={s.path}
              class="w-full text-left px-3 py-1.5 flex items-center gap-2 cursor-pointer file-ac-item"
            >
              <span :if={s.is_git} style="color: var(--accent);">&#x25CF;</span>
              <span :if={!s.is_git} style="color: var(--muted);">&#x25CB;</span>
              <span style="color: var(--text);">{s.name}</span>
              <span class="ml-auto truncate max-w-[180px]" style="color: var(--muted); font-size: var(--font-size-xs);">{s.path}</span>
            </button>
          </div>
        </form>
        <div class="mt-2 text-center" style="color: var(--dim); font-size: var(--font-size-sm);">
          path to project root, or select below
        </div>
        <p :if={@add_project_error} class="mt-1 text-center" style="color: var(--error); font-size: var(--font-size-xs);">
          {@add_project_error}
        </p>
      </div>

      <%!-- Recent projects --%>
      <%= if @projects != [] do %>
        <div class="w-full mt-10">
          <div class="flex items-center gap-1 mb-3 px-3">
            <span style="color: var(--dim);">&#x25BE;</span>
            <span class="section-header">RECENT</span>
          </div>
          <%= for {project, idx} <- Enum.with_index(@projects) do %>
            <.link
              navigate={~p"/projects/#{project.id}"}
              class="block px-6 py-3 cursor-pointer project-landing-item"
              style={"text-decoration: none; #{if idx == @selected_project, do: "background: var(--surface);", else: ""}"}
            >
              <div style={"font-size: 14px; font-weight: 600; color: #{if idx == 0, do: "var(--text)", else: "var(--dim)"};"}>
                {project.name}
              </div>
              <div class="mt-0.5" style="color: var(--muted); font-size: var(--font-size-sm);">
                {shorten_path(project.path)} &middot; {concoction_count_label(project.id)} &middot; {format_relative_time(project.updated_at)}
              </div>
            </.link>
          <% end %>
        </div>
      <% end %>
    </div>
    """
  end

  defp shorten_path(nil), do: ""

  defp shorten_path(path) do
    home = System.get_env("HOME", "")

    if home != "" and String.starts_with?(path, home) do
      "~" <> String.trim_leading(path, home)
    else
      path
    end
  end

  # ── Project Switcher (inline dropdown) ──────────────────

  attr :projects, :list, default: []
  attr :current_project, :any, default: nil
  attr :dispatcher_projects, :map, default: %{}

  def project_switcher(assigns) do
    ~H"""
    <div class="px-3 py-3">
      <%= for project <- @projects do %>
        <% is_current = @current_project && @current_project.id == project.id %>
        <% project_status = @dispatcher_projects[project.id] %>
        <.link
          navigate={~p"/projects/#{project.id}"}
          class="block px-4 py-3 cursor-pointer project-landing-item"
          style={"text-decoration: none; #{if is_current, do: "background: var(--surface);", else: ""}"}
        >
          <div class="flex items-center justify-between">
            <span style={"font-size: 14px; font-weight: 600; color: #{if is_current, do: "var(--text)", else: "var(--dim)"};"}>
              {project.name}
            </span>
            <span :if={is_current} style="color: var(--accent); font-size: var(--font-size-sm);">current</span>
          </div>
          <div class="flex items-center gap-1 mt-0.5" style="color: var(--muted); font-size: var(--font-size-sm);">
            <span>{shorten_path(project.path)}</span>
            <span>&middot;</span>
            <.project_status_dots status={project_status} />
          </div>
        </.link>
      <% end %>

      <div class="mt-3 mx-4" style="border-top: 1px solid var(--border);"></div>

      <.link
        navigate={~p"/"}
        class="block px-4 py-3 cursor-pointer"
        style="text-decoration: none;"
      >
        <span style="color: var(--accent);">+</span>
        <span style="color: var(--dim); font-size: var(--font-size-sm);">&nbsp;open another project</span>
      </.link>
    </div>
    """
  end

  defp project_status_dots(assigns) do
    running = if assigns.status, do: assigns.status[:active_count] || 0, else: 0
    target = if assigns.status, do: assigns.status[:target_count] || 0, else: 0
    is_idle = running == 0 and target == 0

    assigns =
      assigns
      |> assign(:running, running)
      |> assign(:is_idle, is_idle)

    ~H"""
    <%= if @is_idle do %>
      <span>idle</span>
    <% else %>
      <span :if={@running > 0} style="color: var(--concocting);">&#x25C9;{@running}</span>
    <% end %>
    """
  end

  # ── Preview Controls (reusable) ──────────────────────────

  @doc """
  Inline preview controls. Shows config status, start/stop, and port link.

  Modes:
  - `inline: true` — compact for settings bar (no section header)
  - `inline: false` — full block for concoction detail (with PREVIEW header)
  """
  attr :dev_server, :any, default: nil
  attr :has_config, :boolean, default: false
  attr :target_id, :string, required: true
  attr :start_event, :string, default: "start-dev"
  attr :stop_event, :string, default: "stop-dev"
  attr :inline, :boolean, default: false

  def preview_controls(assigns) do
    port =
      case assigns.dev_server do
        %{ports: [%{port: p} | _]} -> p
        _ -> nil
      end

    assigns = assign(assigns, :port, port)

    ~H"""
    <%= if @inline do %>
      <%!-- Inline mode for settings bar --%>
      <%= cond do %>
        <% @dev_server && @dev_server.status == :running -> %>
          <span style="color: var(--accent); font-weight: 500;">
            <a
              href={"http://localhost:#{@port}"}
              target="_blank"
              style="color: var(--accent); text-decoration: none;"
            >
              :{@port} &#x2197;
            </a>
          </span>
          <span style="color: var(--border);">&nbsp;</span>
          <button phx-click={@stop_event} phx-value-id={@target_id} class="cursor-pointer" style="color: var(--muted); font-size: var(--font-size-xs);">
            stop
          </button>

        <% @dev_server && @dev_server.status == :starting -> %>
          <span style="color: var(--concocting);">starting...</span>

        <% @has_config -> %>
          <button phx-click={@start_event} phx-value-id={@target_id} class="cursor-pointer settings-value" style="color: var(--muted);">
            start
          </button>

        <% true -> %>
          <span style="color: var(--muted);">
            no <span style="font-family: monospace; font-size: var(--font-size-xs);">.apothecary/preview.yml</span>
          </span>
      <% end %>
    <% else %>
      <%!-- Block mode for detail panel --%>
      <div class="mb-5">
        <div class="section-header mb-2">PREVIEW</div>
        <%= cond do %>
          <% @dev_server && @dev_server.status == :running -> %>
            <div class="flex items-center gap-2" style="font-size: var(--font-size-sm);">
              <span class="action-text" phx-click="open-preview" phx-value-id={@target_id}>
                p open :{@port}
              </span>
              <span style="color: var(--border);">&middot;</span>
              <span class="action-text" phx-click="view-diff" phx-value-id={@target_id}>d view diff</span>
              <span style="color: var(--border);">&middot;</span>
              <button phx-click={@stop_event} phx-value-id={@target_id} class="action-text">stop</button>
            </div>

          <% @dev_server && @dev_server.status == :starting -> %>
            <span style="color: var(--concocting); font-size: var(--font-size-sm);">starting...</span>

          <% @has_config -> %>
            <div style="font-size: var(--font-size-sm);">
              <span class="action-text" phx-click={@start_event} phx-value-id={@target_id}>
                p start preview
              </span>
            </div>

          <% true -> %>
            <div style="color: var(--muted); font-size: var(--font-size-sm);">
              add <span style="font-family: monospace;">.apothecary/preview.yml</span> to enable preview
            </div>
        <% end %>
      </div>
    <% end %>
    """
  end

  # ── Settings Line ────────────────────────────────────────

  attr :target_count, :integer, default: 1
  attr :auto_pr, :boolean, default: false
  attr :swarm_status, :atom, default: :paused
  attr :dev_server, :any, default: nil
  attr :has_preview_config, :boolean, default: false
  attr :project_id, :string, default: nil
  attr :editing_setting, :atom, default: nil

  def settings_line(assigns) do
    concocting? = assigns.swarm_status == :running
    assigns = assign(assigns, :concocting?, concocting?)

    ~H"""
    <div class="px-4 py-2 flex items-center gap-0" style="font-size: var(--font-size-sm);">
      <%!-- Swarm toggle --%>
      <span style="color: var(--dim);">s</span>&nbsp;
      <button
        phx-click={if @concocting?, do: "stop-swarm", else: "start-swarm"}
        class="cursor-pointer settings-value"
        style={"color: #{if @concocting?, do: "var(--concocting)", else: "var(--muted)"}; font-weight: 500;"}
      >
        {if @concocting?, do: "▶ concocting", else: "■ stopped"}
      </button>

      <span style="color: var(--border);">&nbsp;&nbsp;&middot;&nbsp;&nbsp;</span>

      <%!-- Alchemists --%>
      <span style="color: var(--dim);">a</span>&nbsp;
      <span style="color: var(--dim);">alchemists:</span>
      <%= if @editing_setting == :alchemists do %>
        <span class="inline-flex items-center gap-1 ml-1">
          <button phx-click="decrement-alchemists" class="cursor-pointer" style="color: var(--accent);">&minus;</button>
          <span style="color: var(--text); font-weight: 600;">{@target_count}</span>
          <button phx-click="increment-alchemists" class="cursor-pointer" style="color: var(--accent);">+</button>
          <button phx-click="confirm-setting" class="cursor-pointer" style="color: var(--muted);">&#x2713;</button>
        </span>
      <% else %>
        <button
          phx-click="edit-setting"
          phx-value-setting="alchemists"
          class="cursor-pointer settings-value"
          style="color: var(--text); font-weight: 600;"
        >
          &nbsp;{@target_count}
        </button>
      <% end %>

      <span style="color: var(--border);">&nbsp;&nbsp;&middot;&nbsp;&nbsp;</span>

      <%!-- Auto-PR --%>
      <span style="color: var(--dim);">t</span>&nbsp;
      <span style="color: var(--dim);">auto-pr:</span>
      <button
        phx-click="toggle-auto-pr"
        class="cursor-pointer settings-value"
        style={"color: #{if @auto_pr, do: "var(--accent)", else: "var(--muted)"}; font-weight: 500;"}
      >
        &nbsp;{if @auto_pr, do: "on", else: "off"}
      </button>

      <span style="color: var(--border);">&nbsp;&nbsp;&middot;&nbsp;&nbsp;</span>

      <%!-- Preview (main branch) --%>
      <span style="color: var(--dim);">main</span>&nbsp;
      <.preview_controls
        dev_server={@dev_server}
        has_config={@has_preview_config}
        target_id={@project_id || "project"}
        start_event="start-project-dev"
        stop_event="stop-project-dev"
        inline={true}
      />
    </div>
    """
  end

  # ── Concoction Input ─────────────────────────────────────

  attr :input_focused, :boolean, default: false

  def concoction_input(assigns) do
    ~H"""
    <div class="px-4 py-3">
      <div class="relative">
        <textarea
          id="primary-input"
          rows="1"
          phx-hook="TextareaSubmit"
          phx-focus="input-focus"
          phx-blur="input-blur"
          autocomplete="off"
          class="moonlight-input w-full resize-none"
          style="min-height: 40px; max-height: 120px;"
        ></textarea>
        <div
          id="file-autocomplete-dropdown"
          phx-update="ignore"
          class="hidden absolute left-0 right-0 bottom-full mb-1 max-h-48 overflow-y-auto z-50"
          style="background: var(--surface); border: 1px solid var(--border);"
        >
        </div>
        <button
          id="primary-input-send"
          phx-hook=".TextareaSend"
          type="button"
          class="absolute right-2 top-1/2 -translate-y-1/2 cursor-pointer p-1"
          style="color: var(--muted);"
          title="Send (Enter)"
        >
          <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 20 20" fill="currentColor" class="w-4 h-4">
            <path d="M3.105 2.288a.75.75 0 0 0-.826.95l1.414 4.926A1.5 1.5 0 0 0 5.135 9.25h6.115a.75.75 0 0 1 0 1.5H5.135a1.5 1.5 0 0 0-1.442 1.086l-1.414 4.926a.75.75 0 0 0 .826.95 28.897 28.897 0 0 0 15.293-7.155.75.75 0 0 0 0-1.114A28.897 28.897 0 0 0 3.105 2.288Z" />
          </svg>
        </button>
        <script :type={Phoenix.LiveView.ColocatedHook} name=".TextareaSend">
          export default {
            mounted() {
              this.el.addEventListener("click", () => {
                const textarea = document.getElementById("primary-input")
                if (textarea) {
                  const text = textarea.value.trim()
                  if (text) {
                    this.pushEvent("submit-input", { text })
                    textarea.value = ""
                  }
                }
              })
            }
          }
        </script>
      </div>
      <div class="mt-1" style="color: var(--muted); font-size: var(--font-size-xs);">
        describe a concoction, or ? to ask
      </div>
    </div>
    """
  end

  # ── Concoction Tree ──────────────────────────────────────

  attr :worktrees_by_status, :map, required: true
  attr :agents, :list, default: []
  attr :dev_servers, :map, default: %{}
  attr :selected_card, :integer, default: 0
  attr :card_ids, :list, default: []
  attr :collapsed_done, :boolean, default: true
  attr :adding_ingredient_to, :string, default: nil
  attr :search_mode, :boolean, default: false
  attr :search_query, :string, default: ""

  def concoction_tree(assigns) do
    # Map status groups to display categories
    running = assigns.worktrees_by_status["running"] || []
    pr = assigns.worktrees_by_status["pr"] || []
    ready = assigns.worktrees_by_status["ready"] || []
    blocked = assigns.worktrees_by_status["blocked"] || []
    done = assigns.worktrees_by_status["done"] || []

    concocting = running
    assaying = pr
    queued = ready ++ blocked
    bottled = done

    # Apply search filter
    query = String.downcase(assigns.search_query || "")

    {concocting, assaying, queued, bottled} =
      if query != "" do
        f = fn entries ->
          Enum.filter(entries, fn e ->
            title = (e.worktree.title || e.worktree.id) |> String.downcase()
            String.contains?(title, query)
          end)
        end

        {f.(concocting), f.(assaying), f.(queued), f.(bottled)}
      else
        {concocting, assaying, queued, bottled}
      end

    assigns =
      assigns
      |> assign(:concocting, concocting)
      |> assign(:assaying, assaying)
      |> assign(:queued, queued)
      |> assign(:bottled, bottled)

    ~H"""
    <div class="px-4 py-3">
      <%!-- Search input --%>
      <div :if={@search_mode} class="mb-3 flex items-center gap-2">
        <span style="color: var(--muted);">/</span>
        <form phx-submit="search-select" phx-change="search-tree" class="flex-1">
          <input
            name="query"
            id="tree-search-input"
            autofocus
            placeholder="search..."
            class="search-input"
            value={@search_query}
            phx-focus="input-focus"
            phx-blur="search-blur"
          />
        </form>
      </div>

      <%!-- Concocting group --%>
      <.tree_group
        :if={@concocting != []}
        label="concocting"
        count={length(@concocting)}
        color="var(--concocting)"
        entries={@concocting}
        dot="●"
        dot_class="dot-pulse"
        title_color="var(--text)"
        card_ids={@card_ids}
        selected_card={@selected_card}
        adding_ingredient_to={@adding_ingredient_to}
        animated_header_dot={true}
      />

      <%!-- Assaying group --%>
      <.tree_group
        :if={@assaying != []}
        label="assaying"
        count={length(@assaying)}
        color="var(--assaying)"
        entries={@assaying}
        dot="◎"
        dot_class=""
        title_color="var(--dim)"
        card_ids={@card_ids}
        selected_card={@selected_card}
        status_label="awaiting review"
        adding_ingredient_to={@adding_ingredient_to}
      />

      <%!-- Queued group --%>
      <.tree_group
        :if={@queued != []}
        label="queued"
        count={length(@queued)}
        color="var(--muted)"
        entries={@queued}
        dot="○"
        dot_class=""
        title_color="var(--dim)"
        opacity="0.5"
        card_ids={@card_ids}
        selected_card={@selected_card}
        adding_ingredient_to={@adding_ingredient_to}
      />

      <%!-- Bottled group (collapsed by default) --%>
      <%= if @bottled != [] do %>
        <div
          class="cursor-pointer py-1"
          phx-click="toggle-done-collapsed"
          style="font-size: var(--font-size-sm);"
        >
          <span style="color: var(--bottled);">
            {if @collapsed_done, do: "▸", else: "▾"} bottled ({length(@bottled)})
          </span>
        </div>
        <.tree_group
          :if={!@collapsed_done}
          label={nil}
          count={0}
          color="var(--bottled)"
          entries={@bottled}
          dot="●"
          dot_class=""
          title_color="var(--bottled)"
          card_ids={@card_ids}
          selected_card={@selected_card}
          adding_ingredient_to={@adding_ingredient_to}
        />
      <% end %>

      <%!-- Empty state --%>
      <div
        :if={@concocting == [] && @assaying == [] && @queued == [] && @bottled == []}
        class="py-6"
        style="color: var(--muted); font-size: var(--font-size-sm);"
      >
        no concoctions yet
      </div>
    </div>
    """
  end

  # Tree group component
  attr :label, :any, default: nil
  attr :count, :integer, default: 0
  attr :color, :string, required: true
  attr :entries, :list, required: true
  attr :dot, :string, required: true
  attr :dot_class, :string, default: ""
  attr :title_color, :string, default: "var(--text)"
  attr :opacity, :string, default: "1"
  attr :card_ids, :list, default: []
  attr :selected_card, :integer, default: 0
  attr :status_label, :string, default: nil
  attr :adding_ingredient_to, :string, default: nil
  attr :animated_header_dot, :boolean, default: false

  defp tree_group(assigns) do
    ~H"""
    <div style={"opacity: #{@opacity};"}>
      <div :if={@label} class="py-1" style={"color: #{@color}; font-size: var(--font-size-sm);"}>
        {@label} ({@count})
        <span :if={@animated_header_dot} class="concocting-snake"><span></span><span></span><span></span></span>
      </div>
      <div style="font-size: var(--font-size-sm);">
        <%= for {entry, idx} <- Enum.with_index(@entries) do %>
          <% last? = idx == length(@entries) - 1
             wt = entry.worktree
             selected? = selected_entry?(@card_ids, @selected_card, wt.id)
             tasks = entry.tasks
             done_count = Enum.count(tasks, &(&1.status in ["done", "closed"]))
             total_count = length(tasks)
             port = entry_port(entry.dev_server) %>
          <%!-- Leading connector from group label --%>
          <div :if={@label && idx == 0} class="tree-char pl-1" style="font-size: var(--font-size-sm);">│</div>
          <div
            style={"#{if selected?, do: "border-left: 2px solid var(--accent); background: var(--surface);", else: "border-left: 2px solid transparent;"}"}
            class="cursor-pointer"
            phx-click="select-task"
            phx-value-id={wt.id}
            data-card-id={wt.id}
            data-selected={if(selected?, do: "true")}
          >
            <%!-- Tree line + dot + title --%>
            <div class="flex items-baseline gap-1.5 py-1 px-1">
              <span class="tree-char">{if last?, do: "└─", else: "├─"}</span>
              <span class={@dot_class} style={"color: #{@color};"}>{@dot}</span>
              <span style={"color: #{@title_color}; font-weight: 500;"}>{wt.title || wt.id}</span>
              <span :if={selected?} style="color: var(--accent); margin-left: auto; padding-right: 4px;">◂</span>
            </div>
            <%!-- Metadata line --%>
            <div class="flex items-center gap-1 pl-8 pb-1.5" style="color: var(--muted); font-size: var(--font-size-xs);">
              <span>{wt.id}</span>
              <span :if={total_count > 0}>
                &middot; {done_count}/{total_count} {progress_bar(done_count, total_count)}
              </span>
              <span :if={port}>
                &middot; :{port}
              </span>
              <span :if={@status_label}>
                &middot; {@status_label}
              </span>
            </div>
          </div>
          <%!-- Inline ingredients sub-tree --%>
          <%= if tasks != [] do %>
            <div class="pl-8" style="font-size: var(--font-size-xs);">
              <%= for {task, tidx} <- Enum.with_index(tasks) do %>
                <% tlast? = tidx == length(tasks) - 1
                   {ing_dot, ing_dot_color, ing_dot_class} = ingredient_dot(task.status)
                   ing_text_color = ingredient_text_color(task.status) %>
                <div class="flex items-baseline gap-1.5 py-0.5 px-1">
                  <span class="tree-char">{if tlast?, do: "└─", else: "├─"}</span>
                  <span class={ing_dot_class} style={"color: #{ing_dot_color};"}>{ing_dot}</span>
                  <span style={"color: #{ing_text_color};"}>{task.title}</span>
                </div>
              <% end %>
            </div>
          <% end %>
          <%!-- Inline ingredient input --%>
          <div :if={@adding_ingredient_to == wt.id} class="pl-8 py-1">
            <form phx-submit="add-ingredient-inline">
              <input type="hidden" name="concoction_id" value={wt.id} />
              <input
                name="title"
                id={"ingredient-input-#{wt.id}"}
                autofocus
                phx-blur="ingredient-input-blur"
                placeholder="new ingredient..."
                class="ingredient-inline-input"
                phx-focus="input-focus"
              />
            </form>
          </div>
          <%!-- Connector line between entries (not after last) --%>
          <div :if={!last?} class="tree-char pl-1" style="font-size: var(--font-size-sm);">│</div>
        <% end %>
      </div>
    </div>
    """
  end

  defp progress_bar(done, total) when total > 0 do
    filled = round(done / total * 6)
    String.duplicate("▓", filled) <> String.duplicate("░", 6 - filled)
  end

  defp progress_bar(_, _), do: ""

  defp ingredient_dot(status) when status in ["done", "closed"], do: {"●", "var(--accent)", ""}
  defp ingredient_dot("in_progress"), do: {"∷", "var(--concocting)", "ingredient-dot-active"}
  defp ingredient_dot("blocked"), do: {"○", "var(--error)", ""}
  defp ingredient_dot(_), do: {"○", "var(--muted)", ""}

  defp ingredient_text_color(status) when status in ["done", "closed"], do: "var(--dim)"
  defp ingredient_text_color("in_progress"), do: "var(--text)"
  defp ingredient_text_color(_), do: "var(--muted)"

  defp selected_entry?(card_ids, selected_card, wt_id) do
    case Enum.at(card_ids, selected_card) do
      ^wt_id -> true
      _ -> false
    end
  end

  defp entry_port(%{status: :running, ports: [%{port: p} | _]}), do: p
  defp entry_port(_), do: nil

  # ── Concoction Detail (Full Takeover) ────────────────────

  attr :task, :map, required: true
  attr :children, :list, default: []
  attr :editing_field, :atom, default: nil
  attr :working_agent, :map, default: nil
  attr :agent_output, :list, default: []
  attr :dev_server, :map, default: nil
  attr :has_preview_config, :boolean, default: false
  attr :pending_action, :any, default: nil
  attr :loading_action, :atom, default: nil

  def concoction_detail(assigns) do
    pr_url = Map.get(assigns.task, :pr_url)
    status_group = task_status_group(assigns.task)
    status_color = group_color(status_group)
    status_dot = group_dot(status_group)
    brewer_label = if assigns.working_agent, do: "brewer #{assigns.working_agent.id}", else: nil
    time_ago = format_relative_time(assigns.task.created_at)

    # Git info
    git_changes = Map.get(assigns.task, :git_changes, nil)
    last_commit = Map.get(assigns.task, :last_commit, nil)

    assigns =
      assigns
      |> assign(:pr_url, pr_url)
      |> assign(:status_group, status_group)
      |> assign(:status_color, status_color)
      |> assign(:status_dot, status_dot)
      |> assign(:brewer_label, brewer_label)
      |> assign(:time_ago, time_ago)
      |> assign(:git_changes, git_changes)
      |> assign(:last_commit, last_commit)
      |> assign(:loading?, assigns.loading_action != nil)

    ~H"""
    <div class="px-4 py-4 scroll-main overflow-y-auto flex-1">
      <%!-- 1. Title + Status --%>
      <div class="mb-5">
        <div class="flex items-start justify-between">
          <div class="flex-1 min-w-0">
        <%= if @editing_field == :title do %>
          <.form for={%{}} phx-submit="save-edit" class="mb-2">
            <input type="hidden" name="field" value="title" />
            <input
              type="text"
              name="value"
              value={@task.title}
              autofocus
              phx-focus="input-focus"
              phx-blur="input-blur"
              class="moonlight-input w-full"
              style="font-size: 18px; font-weight: 600;"
            />
            <div class="flex items-center gap-2 mt-1">
              <button type="submit" class="action-pill">save</button>
              <button type="button" phx-click="cancel-edit" class="action-text">cancel</button>
            </div>
          </.form>
        <% else %>
          <div
            phx-click="start-edit"
            phx-value-field="title"
            class="cursor-pointer"
            style="font-size: 18px; font-weight: 600; color: var(--text);"
          >
            {@task.title}
          </div>
        <% end %>
        <div class="flex items-center gap-2 mt-1" style="font-size: var(--font-size-xs); color: var(--muted);">
          <span>{@task.id}</span>
          <span :if={@brewer_label} style="color: var(--dim);">&middot; {@brewer_label}</span>
          <span :if={@time_ago}>&middot; {@time_ago}</span>
        </div>
          </div>
          <button phx-click="deselect-task" class="cursor-pointer flex-shrink-0" style="color: var(--muted); font-size: var(--font-size-xs);">
            esc
          </button>
        </div>
      </div>

      <%!-- 2. Actions --%>
      <div class="flex items-center gap-3 mb-5" style="font-size: var(--font-size-sm);">
        <%= if @loading? do %>
          <div class="flex items-center gap-2">
            <.spinner class="w-3 h-3" />
            <span style="color: var(--dim);">{loading_label(@loading_action)}</span>
          </div>
        <% else %>
          <%= if @pending_action do %>
            <span style="color: var(--concocting);">
              {if match?({:direct_merge, _, _}, @pending_action), do: "merge directly?", else: "merge this PR?"}
            </span>
            <button phx-click="confirm-merge" class="action-pill">confirm</button>
            <button phx-click="cancel-merge" class="action-text">cancel</button>
          <% else %>
            <%= if @task.status in ["brew_done", "done", "closed"] and is_nil(@pr_url) do %>
              <span class="action-pill" phx-click="promote-to-assaying">c create-pr</span>
            <% end %>
            <span :if={@pr_url} class="action-pill" phx-click="merge-pr">m merge</span>
            <span :if={@task.status not in ["done", "closed", "merged"]} class="action-text" phx-click="requeue-task">r requeue</span>
            <span :if={@task.status not in ["done", "closed", "merged"]} class="action-text" phx-click="close-task">x close</span>
          <% end %>
        <% end %>
      </div>

      <%!-- 3. INGREDIENTS --%>
      <div class="mb-5">
        <div class="section-header mb-2">INGREDIENTS</div>
        <%= if @children == [] do %>
          <div style="color: var(--muted); font-size: var(--font-size-sm);">none</div>
        <% else %>
          <div :for={child <- @children} class="flex items-center gap-2 py-1" style="font-size: var(--font-size-sm);">
            <span style={"color: #{if child.status in ["done", "closed"], do: "var(--accent)", else: "var(--concocting)"};"}>
              {if child.status in ["done", "closed"], do: "✓", else: "◌"}
            </span>
            <span style={"color: #{if child.status in ["done", "closed"], do: "var(--dim)", else: "var(--text)"};"}>
              {child.title}
            </span>
            <span class="ml-auto" style="color: var(--muted); font-size: var(--font-size-xxs);">
              {child.id}
            </span>
          </div>
        <% end %>
        <div class="mt-1">
          <span class="action-text" style="color: var(--accent); font-size: var(--font-size-sm);">+ add ingredient</span>
        </div>
      </div>

      <%!-- 4. GIT --%>
      <div :if={@last_commit || @git_changes} class="mb-5">
        <div class="section-header mb-2">GIT</div>
        <div :if={@last_commit} style="font-size: var(--font-size-sm);" class="mb-2">
          <span style="color: var(--text); font-weight: 600;">{String.slice(@last_commit.hash || "", 0..6)}</span>
          <span style="color: var(--dim);">&nbsp;{@last_commit.message}</span>
        </div>
        <div :if={@git_changes} style="font-size: var(--font-size-xs);">
          <div :for={file <- @git_changes.files || []} class="flex items-center gap-2 py-0.5">
            <span style="color: var(--muted);">{file.path}</span>
            <span :if={file.additions > 0} style="color: var(--accent); font-weight: 600;">+{file.additions}</span>
            <span :if={file.deletions > 0} style="color: var(--error); font-weight: 600;">-{file.deletions}</span>
          </div>
          <% file_count = length(@git_changes.files || []) %>
          <% total_add = Enum.sum(Enum.map(@git_changes.files || [], & &1.additions)) %>
          <% total_del = Enum.sum(Enum.map(@git_changes.files || [], & &1.deletions)) %>
          <div class="mt-1" style="color: var(--muted); font-size: var(--font-size-xs);">
            {file_count} {if file_count == 1, do: "file", else: "files"} &middot; +{total_add} -{total_del}
          </div>
        </div>
        <div class="mt-2">
          <span class="action-text" phx-click="view-diff" phx-value-id={@task.id}>d view diff</span>
        </div>
      </div>

      <%!-- 5. PREVIEW --%>
      <.preview_controls
        dev_server={@dev_server}
        has_config={@has_preview_config}
        target_id={@task.id}
        inline={false}
      />

      <%!-- 6. OUTPUT --%>
      <div :if={@agent_output != []} class="mb-5">
        <div class="section-header mb-2">
          OUTPUT &middot; {length(@agent_output)} lines
        </div>
        <.agent_output_panel output={@agent_output} />
      </div>

      <%!-- 7. PR link --%>
      <div :if={@pr_url} class="mb-5">
        <div class="section-header mb-2">PULL REQUEST</div>
        <a
          href={@pr_url}
          target="_blank"
          style="color: var(--accent); font-size: var(--font-size-sm); text-decoration: none;"
        >
          {@pr_url}
        </a>
      </div>

      <%!-- 8. Description --%>
      <div :if={@task.description && @task.description != ""} class="mb-5">
        <div class="section-header mb-2">DESCRIPTION</div>
        <%= if @editing_field == :description do %>
          <.form for={%{}} phx-submit="save-edit">
            <input type="hidden" name="field" value="description" />
            <textarea
              name="value"
              rows="4"
              autofocus
              phx-focus="input-focus"
              phx-blur="input-blur"
              class="moonlight-input w-full"
            >{@task.description}</textarea>
            <div class="flex items-center gap-2 mt-1">
              <button type="submit" class="action-pill">save</button>
              <button type="button" phx-click="cancel-edit" class="action-text">cancel</button>
            </div>
          </.form>
        <% else %>
          <div
            phx-click="start-edit"
            phx-value-field="description"
            class="cursor-pointer"
            style="color: var(--dim); font-size: var(--font-size-sm); white-space: pre-wrap;"
          >
            {@task.description}
          </div>
        <% end %>
      </div>

      <%!-- Notes --%>
      <div :if={@task.notes && @task.notes != ""} class="mb-5">
        <div class="section-header mb-2">NOTES</div>
        <div
          id="task-notes-content"
          style="color: var(--dim); font-size: var(--font-size-xs); white-space: pre-wrap;"
        >
          {@task.notes}
        </div>
        <.copy_button target="#task-notes-content" />
      </div>

      <%!-- 9. MCP SERVERS --%>
      <div class="mb-5">
        <div class="section-header mb-2">MCP SERVERS</div>
        <div style="font-size: var(--font-size-sm);">
          <%= if @task.mcp_servers && map_size(@task.mcp_servers) > 0 do %>
            <span style="color: var(--dim);">{map_size(@task.mcp_servers)} configured</span>
          <% else %>
            <span style="color: var(--dim);">inherited from project</span>
          <% end %>
          <span style="color: var(--accent); font-weight: 600;">&nbsp;+ add</span>
        </div>
      </div>
    </div>
    """
  end

  # ── Agent Output Panel ───────────────────────────────────

  attr :output, :list, default: []

  def agent_output_panel(assigns) do
    ~H"""
    <div
      id="agent-output"
      class="output-box p-2"
      phx-hook="ScrollBottom"
      phx-update="ignore"
    >
      <div
        :for={line <- Enum.take(@output, -50)}
        style={"color: #{if String.starts_with?(line, "[tool:") or String.starts_with?(line, "tool:"), do: "var(--muted)", else: "var(--dim)"}; font-size: var(--font-size-xs);"}
      >
        {line}
      </div>
    </div>
    """
  end

  # ── Status Bar ───────────────────────────────────────────

  attr :selected_task, :any, default: nil
  attr :selected_task_id, :string, default: nil
  attr :worktrees_by_status, :map, default: %{}
  attr :orphan_count, :integer, default: 0
  attr :current_project, :any, default: nil
  attr :active_tab, :atom, default: :workbench
  attr :show_project_switcher, :boolean, default: false
  attr :project_count, :integer, default: 0

  def moonlight_status_bar(assigns) do
    running_count = length(assigns.worktrees_by_status["running"] || [])
    pr_count = length(assigns.worktrees_by_status["pr"] || [])
    queued_count = length((assigns.worktrees_by_status["ready"] || []) ++ (assigns.worktrees_by_status["blocked"] || []))
    done_count = length(assigns.worktrees_by_status["done"] || [])

    assigns =
      assigns
      |> assign(:running_count, running_count)
      |> assign(:pr_count, pr_count)
      |> assign(:queued_count, queued_count)
      |> assign(:done_count, done_count)

    ~H"""
    <div class="status-bar flex items-center justify-between">
      <%= cond do %>
        <% @show_project_switcher -> %>
          <%!-- Switcher status bar --%>
          <div class="flex items-center gap-2">
            <span>&#x2191;/&#x2193; select</span>
            <span style="color: var(--border);">&middot;</span>
            <span>enter switch</span>
            <span style="color: var(--border);">&middot;</span>
            <span>esc cancel</span>
          </div>
          <div style="color: var(--muted);">{@project_count} projects</div>

        <% is_nil(@current_project) -> %>
          <%!-- Landing status bar --%>
          <div class="flex items-center gap-2">
            <span>enter open</span>
            <span style="color: var(--border);">&middot;</span>
            <span>&#x2191;/&#x2193; select</span>
            <span style="color: var(--border);">&middot;</span>
            <span>tab autocomplete path</span>
          </div>
          <div style="color: var(--muted);">v0.1.0</div>

        <% @active_tab == :oracle -> %>
          <%!-- Oracle status bar --%>
          <div class="flex items-center gap-2">
            <span>&#x2191;/&#x2193; history</span>
            <span style="color: var(--border);">&middot;</span>
            <span>enter send</span>
            <span style="color: var(--border);">&middot;</span>
            <span>esc clear</span>
          </div>
          <div style="color: var(--muted);">
            context: <span style="font-weight: 600;">main</span>
          </div>

        <% @active_tab == :workbench && @selected_task_id && @selected_task -> %>
          <%!-- Workbench with selected task --%>
          <div class="flex items-center gap-2">
            <span>j/k nav</span>
            <span style="color: var(--border);">&middot;</span>
            <span>esc close</span>
            <span style="color: var(--border);">&middot;</span>
            <span>p preview</span>
            <span style="color: var(--border);">&middot;</span>
            <span>d diff</span>
            <span style="color: var(--border);">&middot;</span>
            <span>c pr</span>
            <span style="color: var(--border);">&middot;</span>
            <span>m merge</span>
          </div>
          <div class="flex items-center gap-2">
            <span style="color: var(--concocting);">&#x25CF;{@running_count}</span>
            <span style="color: var(--assaying);">&#x25CE;{@pr_count}</span>
            <span style="color: var(--muted);">&#x25CB;{@queued_count}</span>
            <span style="color: var(--bottled);">&#x25CF;{@done_count}</span>
          </div>

        <% true -> %>
          <%!-- Workbench / default status bar --%>
          <div class="flex items-center gap-2">
            <span>j/k nav</span>
            <span style="color: var(--border);">&middot;</span>
            <span>enter inspect</span>
            <span style="color: var(--border);">&middot;</span>
            <span>esc deselect</span>
            <span style="color: var(--border);">&middot;</span>
            <span>a add</span>
            <span style="color: var(--border);">&middot;</span>
            <span>s stop</span>
          </div>
          <div class="flex items-center gap-2">
            <span :if={@running_count > 0} class="snake-dots"><span></span><span></span><span></span></span>
            <span style="color: var(--concocting);">&#x25CF;{@running_count}</span>
            <span style="color: var(--assaying);">&#x25CE;{@pr_count}</span>
            <span style="color: var(--muted);">&#x25CB;{@queued_count}</span>
            <span style="color: var(--bottled);">&#x25CF;{@done_count}</span>
          </div>
      <% end %>
    </div>
    """
  end

  # ── Add Project Modal ────────────────────────────────────

  attr :error, :string, default: nil
  attr :suggestions, :list, default: []

  def add_project_modal(assigns) do
    ~H"""
    <div class="fixed inset-0 z-50 flex items-center justify-center" style="background: rgba(0,0,0,0.6);">
      <div
        class="w-full max-w-md mx-4 p-4"
        style="background: var(--surface); border: 1px solid var(--border);"
        phx-click-away="cancel-add-project"
        phx-window-keydown="cancel-add-project"
        phx-key="Escape"
      >
        <div class="section-header mb-3">OPEN PROJECT</div>
        <form phx-submit="add-project" phx-change="search-project-path">
          <input
            type="text"
            name="path"
            placeholder="/path/to/project"
            autofocus
            autocomplete="off"
            phx-debounce="150"
            class="moonlight-input w-full mb-2"
          />
          <p :if={@error} style="color: var(--error); font-size: var(--font-size-xs);" class="mb-2">{@error}</p>
          <div
            :if={@suggestions != []}
            class="mb-2 max-h-40 overflow-y-auto"
            style="background: var(--bg); border: 1px solid var(--border);"
          >
            <button
              :for={s <- @suggestions}
              type="button"
              phx-click="select-project-path"
              phx-value-path={s.path}
              class="w-full text-left px-3 py-1.5 flex items-center gap-2 cursor-pointer"
              style="font-size: var(--font-size-sm);"
            >
              <span :if={s.is_git} style="color: var(--accent);">●</span>
              <span :if={!s.is_git} style="color: var(--muted);">○</span>
              <span style="color: var(--text);">{s.name}</span>
              <span class="ml-auto truncate max-w-[180px]" style="color: var(--muted); font-size: var(--font-size-xs);">{s.path}</span>
            </button>
          </div>
          <div class="flex justify-end gap-2">
            <button type="button" phx-click="cancel-add-project" class="action-text">cancel</button>
            <button type="submit" class="action-pill">open</button>
          </div>
        </form>
      </div>
    </div>
    """
  end

  # ── New Project Modal ────────────────────────────────────

  attr :error, :string, default: nil
  attr :progress, :string, default: nil

  def new_project_modal(assigns) do
    templates = Apothecary.Bootstrapper.templates()
    assigns = assign(assigns, :templates, templates)

    ~H"""
    <div class="fixed inset-0 z-50 flex items-center justify-center" style="background: rgba(0,0,0,0.6);">
      <div
        class="w-full max-w-md mx-4 p-4"
        style="background: var(--surface); border: 1px solid var(--border);"
        phx-click-away="cancel-new-project"
        phx-window-keydown="cancel-new-project"
        phx-key="Escape"
      >
        <div class="section-header mb-3">NEW PROJECT</div>
        <form phx-submit="create-new-project" id="new-project-form">
          <div class="mb-3">
            <div class="mb-1" style="color: var(--dim); font-size: var(--font-size-xs);">parent directory</div>
            <input
              type="text"
              name="parent_dir"
              value={System.get_env("HOME", "~")}
              class="moonlight-input w-full"
            />
          </div>
          <div class="mb-3">
            <div class="mb-1" style="color: var(--dim); font-size: var(--font-size-xs);">project name</div>
            <input
              type="text"
              name="name"
              placeholder="my_app"
              autofocus
              class="moonlight-input w-full"
            />
          </div>
          <div class="mb-3">
            <div class="mb-1" style="color: var(--dim); font-size: var(--font-size-xs);">template</div>
            <div :for={tmpl <- @templates} class="flex items-center gap-2 py-1">
              <input
                type="radio"
                name="template"
                value={tmpl.id}
                checked={tmpl.id == :phoenix_no_ecto}
                style="accent-color: var(--accent);"
              />
              <span style="color: var(--text); font-size: var(--font-size-sm);">{tmpl.name}</span>
              <span style="color: var(--muted); font-size: var(--font-size-xs);">{tmpl.description}</span>
            </div>
          </div>
          <p :if={@error} style="color: var(--error); font-size: var(--font-size-xs);" class="mb-2">{@error}</p>
          <div :if={@progress} class="flex items-center gap-2 mb-2 p-2" style="background: var(--bg); font-size: var(--font-size-xs); color: var(--dim);">
            <.spinner class="w-3 h-3" />
            <span>{@progress}</span>
          </div>
          <div class="flex justify-end gap-2">
            <button type="button" phx-click="cancel-new-project" class="action-text">cancel</button>
            <button type="submit" disabled={@progress != nil} class="action-pill">
              {if @progress, do: "creating...", else: "create"}
            </button>
          </div>
        </form>
      </div>
    </div>
    """
  end

  # ── Diff Overlay ─────────────────────────────────────────

  attr :diff_view, :any, required: true

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
    <div class="fixed inset-0 z-50 flex flex-col" style="background: var(--bg);">
      <div class="flex items-center justify-between px-4 py-2 shrink-0" style="border-bottom: 1px solid var(--border);">
        <div class="flex items-center gap-3">
          <span class="section-header" style="color: var(--accent);">DIFF</span>
          <span style="color: var(--dim); font-size: var(--font-size-sm);">{@diff.worktree_id}</span>
          <span :if={@diff.loading} style="color: var(--concocting); font-size: var(--font-size-xs);" class="animate-pulse">loading...</span>
        </div>
        <span style="color: var(--muted); font-size: var(--font-size-xs);">esc close  j/k navigate</span>
      </div>

      <div :if={@diff.error && !@diff.loading} class="flex-1 flex items-center justify-center">
        <div class="text-center">
          <div id="diff-error-text" style="color: var(--error); font-size: var(--font-size-sm);">{@diff.error}</div>
          <.copy_button target="#diff-error-text" class="mt-2" />
        </div>
      </div>

      <div :if={@diff.loading} class="flex-1 flex items-center justify-center">
        <span style="color: var(--concocting);" class="animate-pulse">fetching diff...</span>
      </div>

      <div :if={!@diff.loading && !@diff.error && @diff.files != []} class="flex flex-1 overflow-hidden">
        <div id="diff-file-list" class="w-64 shrink-0 overflow-y-auto" style="border-right: 1px solid var(--border); background: var(--surface);">
          <div class="section-header px-3 py-1" style="border-bottom: 1px solid var(--border);">
            files ({length(@diff.files)})
          </div>
          <div
            :for={{file, idx} <- Enum.with_index(@diff.files)}
            data-diff-selected={if(idx == @diff.selected_file, do: "true")}
            class="px-3 py-1 truncate cursor-default"
            style={"font-size: var(--font-size-xs); #{if idx == @diff.selected_file, do: "background: var(--bg); color: var(--accent); border-left: 2px solid var(--accent);", else: "color: var(--dim); border-left: 2px solid transparent;"}"}
          >
            {file.path}
          </div>
        </div>

        <div class="flex-1 overflow-y-auto" id="diff-content-pane">
          <div :if={@current_file} style="font-size: var(--font-size-xs);">
            <div class="sticky top-0 px-4 py-1" style="background: var(--surface); border-bottom: 1px solid var(--border); color: var(--dim);">
              {@current_file.path}
            </div>
            <div
              :for={line <- @current_file.lines}
              class="px-4 whitespace-pre"
              style={diff_line_style(line.type)}
            >
              {line.text}
            </div>
          </div>
        </div>
      </div>

      <div :if={!@diff.loading && !@diff.error && @diff.files == []} class="flex-1 flex items-center justify-center">
        <span style="color: var(--muted);">no changes found</span>
      </div>
    </div>
    """
  end

  defp diff_line_style(:add), do: "background: rgba(90, 170, 154, 0.1); color: var(--accent);"
  defp diff_line_style(:del), do: "background: rgba(196, 90, 90, 0.1); color: var(--error);"
  defp diff_line_style(:hunk), do: "color: var(--dim); background: rgba(90, 122, 130, 0.1);"
  defp diff_line_style(_), do: "color: var(--muted);"

  # ── Which-key Help Overlay ───────────────────────────────

  attr :page, :atom, default: :dashboard
  attr :has_selected_task, :boolean, default: false

  def which_key_overlay(assigns) do
    ~H"""
    <div
      class="fixed inset-0 z-50 flex items-center justify-center"
      style="background: rgba(0,0,0,0.7);"
      phx-click="close-help"
    >
      <div
        class="max-w-xl w-full mx-4 max-h-[80vh] overflow-y-auto p-4"
        style="background: var(--surface); border: 1px solid var(--border);"
        phx-click={%Phoenix.LiveView.JS{}}
      >
        <div class="flex items-center justify-between mb-3">
          <span class="section-header">KEYBINDINGS</span>
          <span style="color: var(--muted); font-size: var(--font-size-xs);">esc close</span>
        </div>

        <div class="grid grid-cols-1 md:grid-cols-2 gap-4" style="font-size: var(--font-size-sm);">
          <div>
            <div style="color: var(--accent);" class="mb-1">navigation</div>
            <.hk key="j/k" desc="next/prev concoction" />
            <.hk key="g/G" desc="first/last concoction" />
            <.hk key="enter" desc="inspect concoction" />
            <.hk key="esc" desc="close / back" />
            <.hk key="/" desc="focus input" />
          </div>

          <div>
            <div style="color: var(--accent);" class="mb-1">tabs</div>
            <.hk key="w" desc="workbench" />
            <.hk key="e" desc="recurring" />
            <.hk key="o" desc="oracle" />
          </div>

          <div>
            <div style="color: var(--accent);" class="mb-1">actions</div>
            <.hk key="s" desc="start/stop concocting" />
            <.hk key="+/-" desc="alchemist count" />
            <.hk key="d" desc="view diff" />
            <.hk key="p" desc="open preview" />
            <.hk key="?" desc="this help" />
          </div>

          <div :if={@has_selected_task}>
            <div style="color: var(--accent);" class="mb-1">detail view</div>
            <.hk key="c" desc="create PR" />
            <.hk key="m" desc="merge" />
            <.hk key="r" desc="requeue" />
            <.hk key="x" desc="close concoction" />
          </div>
        </div>
      </div>
    </div>
    """
  end

  defp hk(assigns) do
    ~H"""
    <div class="flex items-center justify-between gap-3 py-0.5">
      <span style="color: var(--dim);">{@desc}</span>
      <span style="color: var(--concocting);">{@key}</span>
    </div>
    """
  end

  # ── Oracle View ──────────────────────────────────────────

  attr :questions, :list, required: true
  attr :agents, :list, default: []

  def oracle_view(assigns) do
    active_wt_ids =
      assigns.agents
      |> Enum.flat_map(fn a ->
        if a.current_concoction, do: [to_string(a.current_concoction.id)], else: []
      end)
      |> MapSet.new()

    sorted = Enum.sort_by(assigns.questions, fn q -> q.created_at || "" end, :asc)
    assigns = assign(assigns, sorted: sorted, active_wt_ids: active_wt_ids)

    ~H"""
    <div class="px-3 py-3 flex-1 flex flex-col" style="min-height: 0;">
      <div class="mb-3" style="color: var(--muted); font-size: var(--font-size-xs);">
        context: <span style="font-weight: 600;">main</span> &middot; read-only &middot; no mutations
      </div>

      <%= if @sorted == [] do %>
        <div class="flex-1 flex items-center justify-center" style="color: var(--muted); font-size: var(--font-size-sm);">
          <div class="text-center">
            <div class="mb-1">no questions yet</div>
            <div style="font-size: var(--font-size-xs);">ask about the codebase below</div>
          </div>
        </div>
      <% else %>
        <div id="oracle-messages" class="flex-1 overflow-y-auto scroll-main" phx-hook=".OracleScroll">
          <%= for q <- @sorted do %>
            <%!-- User question --%>
            <div class="mb-3">
              <div class="mb-1" style="color: var(--muted); font-size: var(--font-size-xs);">
                you &middot; {format_relative_time(q.created_at)}
              </div>
              <div style="color: var(--text); font-size: var(--font-size-sm); font-weight: 600;">
                {q.title}
              </div>
            </div>

            <%!-- Oracle response --%>
            <%= if q.notes && q.notes != "" do %>
              <div class="oracle-response mb-4 py-2 px-3">
                <div class="mb-1" style="color: var(--muted); font-size: var(--font-size-xs);">
                  oracle &middot; {format_relative_time(q.created_at)}
                </div>
                <div class="oracle-body" style="font-size: var(--font-size-sm);">
                  {format_oracle_response(q.notes)}
                </div>
              </div>
            <% else %>
              <div :if={MapSet.member?(@active_wt_ids, q.id)} class="mb-4 py-2 px-3" style="background: var(--surface); border-left: 2px solid var(--concocting);">
                <div class="flex items-center gap-2" style="color: var(--concocting); font-size: var(--font-size-xs);">
                  <span class="dot-pulse">&#x25C9;</span>
                  <span>thinking...</span>
                </div>
              </div>
            <% end %>
          <% end %>
        </div>
      <% end %>

      <%!-- Oracle input --%>
      <div class="pt-2 mt-auto">
        <div class="relative">
          <textarea
            id="oracle-input"
            rows="1"
            phx-hook=".OracleInput"
            autocomplete="off"
            class="moonlight-input w-full resize-none"
            style="min-height: 32px; max-height: 120px;"
            placeholder="ask about the codebase"
          ></textarea>
          <button
            id="oracle-input-send"
            phx-hook=".OracleSend"
            type="button"
            class="absolute right-2 top-1/2 -translate-y-1/2 cursor-pointer p-1"
            style="color: var(--muted);"
            title="Send (Enter)"
          >
            <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 20 20" fill="currentColor" class="w-4 h-4">
              <path d="M3.105 2.288a.75.75 0 0 0-.826.95l1.414 4.926A1.5 1.5 0 0 0 5.135 9.25h6.115a.75.75 0 0 1 0 1.5H5.135a1.5 1.5 0 0 0-1.442 1.086l-1.414 4.926a.75.75 0 0 0 .826.95 28.897 28.897 0 0 0 15.293-7.155.75.75 0 0 0 0-1.114A28.897 28.897 0 0 0 3.105 2.288Z" />
            </svg>
          </button>
          <script :type={Phoenix.LiveView.ColocatedHook} name=".OracleSend">
            export default {
              mounted() {
                this.el.addEventListener("click", () => {
                  const textarea = document.getElementById("oracle-input")
                  if (textarea) {
                    const text = textarea.value.trim()
                    if (text) {
                      this.pushEvent("oracle-ask", { text })
                      textarea.value = ""
                    }
                  }
                })
              }
            }
          </script>
          <script :type={Phoenix.LiveView.ColocatedHook} name=".OracleInput">
            export default {
              mounted() {
                this.el.addEventListener("keydown", (e) => {
                  if (e.key === "Enter" && !e.shiftKey) {
                    e.preventDefault()
                    const text = this.el.value.trim()
                    if (text) {
                      this.pushEvent("oracle-ask", { text })
                      this.el.value = ""
                    }
                  }
                })
              }
            }
          </script>
          <script :type={Phoenix.LiveView.ColocatedHook} name=".OracleScroll">
            export default {
              mounted() { this.scrollToBottom() },
              updated() { this.scrollToBottom() },
              scrollToBottom() {
                this.el.scrollTop = this.el.scrollHeight
              }
            }
          </script>
        </div>
        <div class="mt-1" style="color: var(--muted); font-size: var(--font-size-xs);">
          ask about the codebase &mdash; oracle reads but never writes
        </div>
      </div>
    </div>
    """
  end

  defp format_oracle_response(notes) do
    answer =
      case String.split(notes, "Answer:\n", parts: 2) do
        [_before, answer] -> String.trim(answer)
        _ -> notes
      end

    answer
    |> split_oracle_blocks()
    |> Enum.map(&render_oracle_block/1)
    |> Enum.join()
    |> Phoenix.HTML.raw()
  end

  defp split_oracle_blocks(text) do
    parts = Regex.split(~r/```(\w*)\n(.*?)```/s, text, include_captures: true)

    Enum.flat_map(parts, fn part ->
      case Regex.run(~r/\A```(\w*)\n(.*?)```\z/s, part) do
        [_, lang, code] -> [{:code, lang, code}]
        _ -> [{:text, part}]
      end
    end)
  end

  defp render_oracle_block({:code, _lang, code}) do
    escaped = Phoenix.HTML.html_escape(String.trim_trailing(code))

    "<div class=\"oracle-code-block\"><pre><code>" <>
      Phoenix.HTML.safe_to_string(escaped) <>
      "</code></pre></div>"
  end

  defp render_oracle_block({:text, text}) do
    text
    |> Phoenix.HTML.html_escape()
    |> Phoenix.HTML.safe_to_string()
    |> highlight_bold()
    |> highlight_inline_code()
    |> highlight_file_paths()
    |> highlight_numbered_lists()
    |> String.replace("\n", "<br>")
  end

  defp highlight_bold(text) do
    Regex.replace(~r/\*\*(.+?)\*\*/, text, "<strong style=\"color: var(--text);\">\\1</strong>")
  end

  defp highlight_inline_code(text) do
    Regex.replace(
      ~r/`([^`]+?)`/,
      text,
      "<code style=\"color: var(--accent); background: var(--surface); padding: 1px 4px; border-radius: 3px;\">\\1</code>"
    )
  end

  @file_path_regex ~r/(?<![<&\w\/])([a-zA-Z_][a-zA-Z0-9_.\/\-]*\.[a-zA-Z]{1,6}(?::\d+)?)/

  defp highlight_file_paths(text) do
    Regex.replace(
      @file_path_regex,
      text,
      "<span class=\"oracle-file-path\">\\1</span>"
    )
  end

  defp highlight_numbered_lists(text) do
    Regex.replace(
      ~r/(\d+)\. /,
      text,
      "<span style=\"color: var(--accent);\">\\1.</span> "
    )
  end

  # ── Recipe List ──────────────────────────────────────────

  attr :recipes, :list, required: true
  attr :show_recipe_form, :boolean, default: false
  attr :recipe_form, :any, default: nil
  attr :editing_recipe_id, :string, default: nil

  def recipe_list(assigns) do
    active = Enum.filter(assigns.recipes, & &1.enabled)
    paused = Enum.reject(assigns.recipes, & &1.enabled)

    next_run =
      active
      |> Enum.map(& &1.next_run_at)
      |> Enum.reject(&is_nil/1)
      |> Enum.sort()
      |> List.first()

    assigns =
      assigns
      |> assign(:active, active)
      |> assign(:paused, paused)
      |> assign(:next_run, next_run)

    ~H"""
    <div class="px-3 py-3">
      <%!-- Summary line --%>
      <div class="mb-3" style="font-size: var(--font-size-xs);">
        <span style="color: var(--dim);">active:</span>
        <span style="color: var(--text);">&nbsp;{length(@active)}</span>
        <span style="color: var(--border);">&nbsp;&middot;&nbsp;</span>
        <span style="color: var(--dim);">paused:</span>
        <span style="color: var(--text);">&nbsp;{length(@paused)}</span>
        <span :if={@next_run} style="color: var(--border);">&nbsp;&middot;&nbsp;</span>
        <span :if={@next_run} style="color: var(--dim);">next run {format_relative_time(@next_run)}</span>
      </div>

      <.recipe_form :if={@show_recipe_form} form={@recipe_form} editing_id={@editing_recipe_id} />

      <%= if @recipes == [] and !@show_recipe_form do %>
        <div style="color: var(--muted); font-size: var(--font-size-sm);" class="py-6">
          no recurring concoctions yet
        </div>
      <% else %>
        <%!-- Active group --%>
        <.recipe_tree_group
          :if={@active != []}
          label="active"
          count={length(@active)}
          color="var(--accent)"
          entries={@active}
          symbol="↻"
          opacity="1"
        />

        <%!-- Paused group --%>
        <.recipe_tree_group
          :if={@paused != []}
          label="paused"
          count={length(@paused)}
          color="var(--muted)"
          entries={@paused}
          symbol="⏸"
          opacity="0.5"
        />
      <% end %>

      <div :if={!@show_recipe_form} class="mt-3">
        <button phx-click="show-recipe-form" style="color: var(--muted); font-size: var(--font-size-sm); cursor: pointer;">
          + new recipe
        </button>
      </div>
    </div>
    """
  end

  attr :form, :any, required: true
  attr :editing_id, :string, default: nil

  defp recipe_form(assigns) do
    ~H"""
    <div class="mb-4 p-3" style="border: 1px solid var(--border);">
      <div class="flex items-center justify-between mb-2">
        <span class="section-header">{if(@editing_id, do: "EDIT RECIPE", else: "NEW RECIPE")}</span>
        <button phx-click="cancel-recipe-form" class="action-text">cancel</button>
      </div>
      <.form for={@form} id="recipe-form" phx-submit="save-recipe">
        <input type="hidden" name="recipe[id]" value={@editing_id} />
        <div class="mb-2">
          <div class="mb-1" style="color: var(--dim); font-size: var(--font-size-xs);">title</div>
          <input
            type="text"
            name="recipe[title]"
            value={@form[:title].value}
            placeholder="e.g. Daily dependency updates"
            class="moonlight-input w-full"
            required
          />
        </div>
        <div class="mb-2">
          <div class="mb-1" style="color: var(--dim); font-size: var(--font-size-xs);">description</div>
          <textarea
            name="recipe[description]"
            rows="3"
            placeholder="Task description for the concoction..."
            class="moonlight-input w-full resize-none"
          >{@form[:description].value}</textarea>
        </div>
        <div class="grid grid-cols-2 gap-3 mb-2">
          <div>
            <div class="mb-1" style="color: var(--dim); font-size: var(--font-size-xs);">schedule (cron)</div>
            <input
              type="text"
              name="recipe[schedule]"
              value={@form[:schedule].value}
              placeholder="0 9 * * MON-FRI"
              class="moonlight-input w-full"
              required
            />
          </div>
          <div>
            <div class="mb-1" style="color: var(--dim); font-size: var(--font-size-xs);">priority</div>
            <select name="recipe[priority]" class="moonlight-input w-full">
              <option value="0" selected={@form[:priority].value == "0"}>P0 - Critical</option>
              <option value="1" selected={@form[:priority].value == "1"}>P1 - High</option>
              <option value="2" selected={@form[:priority].value == "2"}>P2 - Medium</option>
              <option value="3" selected={@form[:priority].value in [nil, "", "3"]}>P3 - Default</option>
              <option value="4" selected={@form[:priority].value == "4"}>P4 - Backlog</option>
            </select>
          </div>
        </div>
        <div class="flex justify-end">
          <button type="submit" class="action-pill">
            {if(@editing_id, do: "update", else: "create")}
          </button>
        </div>
      </.form>
    </div>
    """
  end

  attr :label, :string, required: true
  attr :count, :integer, required: true
  attr :color, :string, required: true
  attr :entries, :list, required: true
  attr :symbol, :string, required: true
  attr :opacity, :string, default: "1"

  defp recipe_tree_group(assigns) do
    ~H"""
    <div style={"opacity: #{@opacity};"}>
      <div class="py-1" style={"color: #{@color}; font-size: var(--font-size-sm);"}>
        {@label} ({@count})
      </div>
      <div style="font-size: var(--font-size-sm);">
        <%= for {recipe, idx} <- Enum.with_index(@entries) do %>
          <% last? = idx == length(@entries) - 1 %>
          <div class="cursor-pointer" phx-click="edit-recipe" phx-value-id={recipe.id}>
            <div class="flex items-baseline gap-1 py-0.5 px-1">
              <span class="tree-char">{if last?, do: "└─", else: "├─"}</span>
              <span style={"color: #{@color};"}>{@symbol}</span>
              <span style="color: var(--text);">{recipe.title}</span>
            </div>
            <div class="flex items-center gap-1 pl-7 pb-1" style="color: var(--muted); font-size: var(--font-size-xs);">
              <span style="color: var(--dim);">{recipe.schedule}</span>
              <span :if={recipe.last_run_at}>&middot; last: {format_relative_time(recipe.last_run_at)}</span>
              <span :if={recipe.next_run_at}>&middot; next: {format_relative_time(recipe.next_run_at)}</span>
              <span class="ml-auto flex items-center gap-1">
                <button phx-click="toggle-recipe" phx-value-id={recipe.id} class="action-text" style="font-size: var(--font-size-xs);">
                  {if(recipe.enabled, do: "pause", else: "resume")}
                </button>
                <button phx-click="delete-recipe" phx-value-id={recipe.id} class="action-text" style="font-size: var(--font-size-xs);" data-confirm="Delete this recipe?">
                  delete
                </button>
              </span>
            </div>
          </div>
          <div :if={!last?} class="tree-char pl-1" style="font-size: var(--font-size-sm);">│</div>
        <% end %>
      </div>
    </div>
    """
  end

  # ── Tab Navigation (for backward compat) ─────────────────

  attr :active_tab, :atom, required: true

  def tab_navigation(assigns) do
    ~H"""
    <div class="flex items-center gap-3">
      <button
        :for={{tab, label} <- [workbench: "workbench", oracle: "oracle", recipes: "recurring"]}
        phx-click="switch-tab"
        phx-value-tab={tab}
        class="cursor-pointer"
        style={"color: #{if @active_tab == tab, do: "var(--text)", else: "var(--muted)"}; font-size: var(--font-size-sm);"}
      >
        {label}
      </button>
    </div>
    """
  end

  # ── Section Header (used by AgentLive) ────────────────────

  attr :label, :string, required: true

  def section(assigns) do
    ~H"""
    <div class="section-header">{@label}</div>
    """
  end

  # ── Status Bar (used by AgentLive) ───────────────────────

  attr :page, :atom, default: :dashboard
  attr :swarm_status, :atom, default: :paused
  attr :agent_count, :integer, default: 0
  attr :orphan_count, :integer, default: 0

  def status_bar(assigns) do
    ~H"""
    <div class="status-bar flex items-center justify-between">
      <span>{page_label(@page)}</span>
      <span>? help</span>
    </div>
    """
  end

  defp page_label(:dashboard), do: "NORMAL"
  defp page_label(:agent), do: "ALCHEMIST"
  defp page_label(_), do: ""

  # ── Agent Status Badge (used by AgentLive) ───────────────

  attr :status, :atom, default: :idle

  def agent_status_badge(assigns) do
    ~H"""
    <span style={"color: #{agent_status_color(@status)};"}>
      {Atom.to_string(@status)}
    </span>
    """
  end

  defp agent_status_color(:working), do: "var(--accent)"
  defp agent_status_color(:idle), do: "var(--concocting)"
  defp agent_status_color(:starting), do: "var(--dim)"
  defp agent_status_color(:error), do: "var(--error)"
  defp agent_status_color(_), do: "var(--muted)"

  # ── Helper functions ─────────────────────────────────────

  defp task_status_group(task) do
    case task.status do
      s when s in ["in_progress", "claimed"] -> "concocting"
      s when s in ["brew_done", "pr_open", "revision_needed"] -> "assaying"
      s when s in ["done", "closed", "merged"] -> "bottled"
      _ -> "queued"
    end
  end

  defp group_color("concocting"), do: "var(--concocting)"
  defp group_color("assaying"), do: "var(--assaying)"
  defp group_color("bottled"), do: "var(--bottled)"
  defp group_color("queued"), do: "var(--muted)"
  defp group_color(_), do: "var(--dim)"

  defp group_dot("concocting"), do: "◉"
  defp group_dot("assaying"), do: "◎"
  defp group_dot("bottled"), do: "●"
  defp group_dot("queued"), do: "○"
  defp group_dot(_), do: "·"

  defp loading_label(:merging), do: "merging PR..."
  defp loading_label(:direct_merging), do: "creating PR & merging..."
  defp loading_label(:creating_pr), do: "creating PR..."
  defp loading_label(_), do: "working..."

  defp concoction_count_label(project_id) do
    count = length(Apothecary.Ingredients.list_concoctions(project_id: project_id))

    case count do
      0 -> "0 concoctions"
      1 -> "1 concoction"
      n -> "#{n} concoctions"
    end
  end

  defp format_relative_time(nil), do: nil

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
