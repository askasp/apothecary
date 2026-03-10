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
    <svg
      class={["animate-spin", @class]}
      style="color: var(--dim);"
      xmlns="http://www.w3.org/2000/svg"
      fill="none"
      viewBox="0 0 24 24"
    >
      <circle class="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" stroke-width="4" />
      <path
        class="opacity-75"
        fill="currentColor"
        d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4zm2 5.291A7.962 7.962 0 014 12H0c0 3.042 1.135 5.824 3 7.938l3-2.647z"
      />
    </svg>
    """
  end

  # ── Braille Spinner ─────────────────────────────────────

  @doc """
  Braille character spinner — a dot chases around the 2×4 braille grid.
  Use `offset` to desync multiple spinners on screen.
  `type` can be :spinner (braille) or :bubbles (ambient ·∘°).
  """
  attr :id, :string, required: true
  attr :offset, :integer, default: 0
  attr :type, :atom, default: :spinner

  def braille_spinner(assigns) do
    ~H"""
    <span
      id={@id}
      phx-hook=".BrailleSpinner"
      data-offset={@offset}
      data-type={@type}
      phx-update="ignore"
    >
      {if @type == :bubbles, do: "·∘°·", else: "⠋"}
    </span>
    <script :type={Phoenix.LiveView.ColocatedHook} name=".BrailleSpinner">
      export default {
        SPINNER: ["⠋","⠙","⠹","⠸","⠼","⠴","⠦","⠧","⠇","⠏"],
        BUBBLES: ["·∘°·","°·∘°","∘°·∘","·∘°·"],
        mounted() {
          this.offset = parseInt(this.el.dataset.offset || "0", 10)
          this.type = this.el.dataset.type || "spinner"
          // Use a shared global counter so all spinners stay in sync (with offsets)
          if (!window.__brailleListeners) {
            window.__brailleFrame = 0
            window.__brailleListeners = new Set()
            window.__brailleIv = setInterval(() => {
              window.__brailleFrame++
              window.__brailleListeners.forEach(fn => fn())
            }, 100)
          }
          this.update = () => {
            const f = window.__brailleFrame
            if (this.type === "bubbles") {
              this.el.textContent = this.BUBBLES[(f + this.offset) % this.BUBBLES.length]
            } else {
              this.el.textContent = this.SPINNER[(f + this.offset) % this.SPINNER.length]
            }
          }
          window.__brailleListeners.add(this.update)
          this.update()
        },
        destroyed() {
          window.__brailleListeners.delete(this.update)
          if (window.__brailleListeners.size === 0) {
            clearInterval(window.__brailleIv)
            window.__brailleFrame = undefined
            window.__brailleListeners = undefined
            window.__brailleIv = undefined
          }
        }
      }
    </script>
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
  attr :theme, :string, default: "moonlight"

  def top_bar(assigns) do
    ~H"""
    <div
      class="flex items-center justify-between px-4 py-3"
      style="font-size: var(--font-size-sm);"
    >
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
      <div class="flex items-center gap-4">
        <%!-- Theme toggle --%>
        <div class="theme-toggle">
          <button
            :for={t <- ~w(moonlight studio daylight)}
            phx-click="set-theme"
            phx-value-theme={t}
            type="button"
            class={"theme-toggle-option #{if @theme == t, do: "theme-toggle-option--active"}"}
          >
            {t}
          </button>
        </div>
        <%!-- Tab navigation --%>
        <%= if @current_project do %>
          <div
            class="flex items-center gap-3"
            style="border-left: 1px solid var(--border); padding-left: 12px;"
          >
            <button
              :for={{tab, label} <- [workbench: "workbench", recipes: "recurring"]}
              phx-click="switch-tab"
              phx-value-tab={tab}
              class="cursor-pointer"
              style={"color: #{if @active_tab == tab, do: "var(--text)", else: "var(--muted)"}; font-size: var(--font-size-sm);"}
            >
              {label}
            </button>
          </div>
        <% end %>
      </div>
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
      <div
        class="mb-8"
        style="color: var(--dim); font-size: var(--font-size-sm); letter-spacing: 0.08em; text-transform: uppercase;"
      >
        NO PROJECT OPEN
      </div>

      <%!-- Path input — full width within the column --%>
      <div class="w-full max-w-[480px]">
        <form phx-submit="add-project" phx-change="search-project-path" class="relative">
          <input
            type="text"
            name="path"
            id="project-path-input"
            value="~/"
            autofocus
            autocomplete="off"
            phx-debounce="150"
            phx-focus="input-focus"
            phx-blur="input-blur"
            class="moonlight-input w-full"
            style="caret-color: var(--accent); padding: 16px 20px; font-size: var(--font-size-base);"
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
              <span
                class="ml-auto truncate max-w-[180px]"
                style="color: var(--muted); font-size: var(--font-size-xs);"
              >
                {s.path}
              </span>
            </button>
          </div>
        </form>
        <div class="mt-2 text-center" style="color: var(--dim); font-size: var(--font-size-sm);">
          path to project root, or select below
        </div>
        <p
          :if={@add_project_error}
          class="mt-1 text-center"
          style="color: var(--error); font-size: var(--font-size-xs);"
        >
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
            <% selected? = idx == @selected_project %>
            <.link
              navigate={~p"/projects/#{project.id}"}
              class="block px-6 py-3 cursor-pointer project-landing-item"
              style={"text-decoration: none; #{if selected?, do: "border-left: 2px solid var(--accent); background: var(--surface);", else: "border-left: 2px solid transparent;"}"}
            >
              <div class="flex items-center justify-between">
                <span style={"font-size: var(--font-size-base); font-weight: 600; color: #{if selected?, do: "var(--text)", else: "var(--dim)"};"}>
                  {project.name}
                </span>
                <span :if={selected?} style="color: var(--accent);">◂</span>
              </div>
              <div class="mt-0.5" style="color: var(--muted); font-size: var(--font-size-sm);">
                {shorten_path(project.path)} &middot; {worktree_count_label(project.id)} &middot; {format_relative_time(
                  project.updated_at
                )}
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

  # ── Project Switcher (dropdown overlay) ──────────────────

  attr :projects, :list, default: []
  attr :current_project, :any, default: nil
  attr :dispatcher_projects, :map, default: %{}
  attr :selected_index, :integer, default: 0
  attr :query, :string, default: ""

  def project_switcher(assigns) do
    ~H"""
    <div
      class="switcher-backdrop"
      phx-click="close-project-switcher"
    >
      <div
        class="switcher-dropdown"
        phx-click-away="close-project-switcher"
        data-project-switcher
      >
        <div class="px-3 pt-3 pb-2">
          <form phx-change="switcher-search" phx-submit="switcher-select">
            <input
              type="text"
              id="project-switcher-search"
              name="query"
              value={@query}
              autocomplete="off"
              phx-debounce="80"
              placeholder="search projects..."
              class="switcher-input"
            />
          </form>
        </div>

        <div class="switcher-list">
          <%= for {project, idx} <- Enum.with_index(@projects) do %>
            <% is_current = @current_project && @current_project.id == project.id %>
            <% selected? = idx == @selected_index %>
            <% project_status = @dispatcher_projects[project.id] %>
            <.link
              navigate={~p"/projects/#{project.id}"}
              class={["switcher-item", selected? && "switcher-item--selected"]}
              data-selected={if(selected?, do: "true")}
              data-switcher-index={idx}
              phx-mouseover="switcher-hover"
              phx-value-index={idx}
            >
              <div class="flex items-center justify-between">
                <span class={["switcher-item-name", selected? && "switcher-item-name--selected"]}>
                  <.fuzzy_name name={project.name} query={@query} />
                </span>
                <span :if={is_current} class="switcher-current-badge">
                  current
                </span>
              </div>
              <div class="switcher-item-meta">
                <span>{shorten_path(project.path)}</span>
                <span>&middot;</span>
                <.project_status_dots status={project_status} />
              </div>
            </.link>
          <% end %>

          <div
            :if={@projects == []}
            class="px-4 py-3"
            style="color: var(--muted); font-size: var(--font-size-sm);"
          >
            no matches
          </div>
        </div>

        <div class="switcher-divider"></div>

        <% add_selected? = @selected_index >= length(@projects) %>
        <.link
          navigate={~p"/"}
          class={["switcher-item switcher-add", add_selected? && "switcher-item--selected"]}
          data-selected={if(add_selected?, do: "true")}
        >
          <span style="color: var(--accent);">+</span>
          <span style="color: var(--dim); font-size: var(--font-size-sm);">
            &nbsp;open another project
          </span>
        </.link>

        <div class="switcher-footer">
          <span>j/k navigate</span>
          <span>&middot;</span>
          <span>enter select</span>
          <span>&middot;</span>
          <span>esc close</span>
        </div>
      </div>
    </div>
    """
  end

  defp fuzzy_name(assigns) do
    highlights = fuzzy_highlight(assigns.name, assigns.query)
    assigns = assign(assigns, :highlights, highlights)

    ~H"""
    <%= for {char, matched?} <- @highlights do %>
      <span :if={matched?} class="fuzzy-match">{char}</span><span :if={!matched?}>{char}</span>
    <% end %>
    """
  end

  defp fuzzy_highlight(name, nil), do: Enum.map(String.graphemes(name), &{&1, false})
  defp fuzzy_highlight(name, ""), do: Enum.map(String.graphemes(name), &{&1, false})

  defp fuzzy_highlight(name, query) do
    name_chars = String.graphemes(name)
    query_chars = String.graphemes(String.downcase(query))
    do_fuzzy_highlight(name_chars, query_chars, [])
  end

  defp do_fuzzy_highlight([], _query, acc), do: Enum.reverse(acc)

  defp do_fuzzy_highlight(remaining, [], acc) do
    Enum.reverse(acc) ++ Enum.map(remaining, &{&1, false})
  end

  defp do_fuzzy_highlight([h | t1], [q | t2], acc) do
    if String.downcase(h) == q do
      do_fuzzy_highlight(t1, t2, [{h, true} | acc])
    else
      do_fuzzy_highlight(t1, [q | t2], [{h, false} | acc])
    end
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
  - `inline: false` — full block for worktree detail (with PREVIEW header)
  """
  attr :dev_server, :any, default: nil
  attr :has_config, :boolean, default: false
  attr :target_id, :string, required: true
  attr :start_event, :string, default: "start-dev"
  attr :stop_event, :string, default: "stop-dev"
  attr :inline, :boolean, default: false

  def preview_controls(assigns) do
    ports =
      case assigns.dev_server do
        %{ports: ports} when is_list(ports) and ports != [] -> ports
        _ -> []
      end

    first_port =
      case ports do
        [%{port: p} | _] -> p
        _ -> nil
      end

    assigns = assign(assigns, port: first_port, ports: ports)

    ~H"""
    <%= if @inline do %>
      <%!-- Inline mode for settings bar --%>
      <%= cond do %>
        <% @dev_server && @dev_server.status == :running -> %>
          <%= if length(@ports) > 1 do %>
            <span
              class="cursor-pointer"
              style="color: var(--accent); text-decoration: none;"
              phx-click="show-preview-picker"
            >
              preview
            </span>
          <% else %>
            <span style="color: var(--dim);">preview</span>
            &nbsp;
            <span
              class="cursor-pointer"
              style="color: var(--accent); text-decoration: none;"
              phx-click="show-preview"
              phx-value-port={@port}
            >
              :{@port}
            </span>
          <% end %>
          &nbsp;
          <button phx-click={@stop_event} phx-value-id={@target_id} class="action-text">
            stop
          </button>
        <% @dev_server && @dev_server.status == :starting -> %>
          <span style="color: var(--dim);">preview</span>
          &nbsp;
          <span
            class="cursor-pointer"
            style="color: var(--concocting);"
            phx-click="show-preview"
            phx-value-port={@port}
          >
            <.braille_spinner id="preview-start-spinner" offset={0} /> starting...
          </span>
        <% @dev_server && @dev_server.status == :error -> %>
          <span style="color: var(--dim);">preview</span>
          &nbsp;
          <span
            class="cursor-pointer"
            style="color: var(--error);"
            phx-click="show-preview"
            phx-value-port={@port || 0}
          >
            crashed
          </span>
          &nbsp;
          <button phx-click={@start_event} phx-value-id={@target_id} class="action-text">
            restart
          </button>
        <% @has_config -> %>
          <button
            phx-click={@start_event}
            phx-value-id={@target_id}
            class="cursor-pointer settings-value"
            style="color: var(--muted);"
          >
            preview
          </button>
        <% true -> %>
          <button
            phx-click="toggle-preview-help"
            class="cursor-pointer"
            style="color: var(--muted);"
            title="How to set up preview"
          >
            preview <span style="color: var(--accent);">?</span>
          </button>
      <% end %>
    <% else %>
      <%!-- Block mode for detail panel --%>
      <div class="mb-5">
        <div class="section-header mb-2">PREVIEW</div>
        <%= cond do %>
          <% @dev_server && @dev_server.status == :running -> %>
            <div style="font-size: var(--font-size-sm);">
              <%= if length(@ports) > 1 do %>
                <%!-- Multiple ports: show each as a separate preview link --%>
                <div class="flex flex-wrap items-center gap-x-1">
                  <%= for {port_info, idx} <- Enum.with_index(@ports) do %>
                    <span
                      class="action-text"
                      phx-click="show-preview"
                      phx-value-port={port_info.port}
                    >
                      :{port_info.port}
                      <span style="color: var(--muted); font-weight: 400;">
                        {port_info.name}
                      </span>
                    </span>
                    <%= if idx < length(@ports) - 1 do %>
                      <span style="color: var(--border);">&middot;</span>
                    <% end %>
                  <% end %>
                  <span style="color: var(--border);">&middot;</span>
                  <button phx-click={@stop_event} phx-value-id={@target_id} class="action-text">
                    stop
                  </button>
                  <span style="color: var(--border);">&middot;</span>
                  <button phx-click="restart-preview" phx-value-id={@target_id} class="action-text">
                    restart
                  </button>
                </div>
              <% else %>
                <%!-- Single port: original compact layout --%>
                <span class="action-text" phx-click="show-preview" phx-value-port={@port}>
                  p preview :{@port}
                </span>
                <span style="color: var(--border);">&nbsp;&middot;&nbsp;</span>
                <a
                  href={"http://localhost:#{@port}"}
                  target="_blank"
                  style="color: var(--dim); text-decoration: none;"
                >
                  open &#x2197;
                </a>
                <span style="color: var(--border);">&nbsp;&middot;&nbsp;</span>
                <button phx-click={@stop_event} phx-value-id={@target_id} class="action-text">
                  stop
                </button>
                <span style="color: var(--border);">&nbsp;&middot;&nbsp;</span>
                <button phx-click="restart-preview" phx-value-id={@target_id} class="action-text">
                  restart
                </button>
              <% end %>
            </div>
          <% @dev_server && @dev_server.status == :starting -> %>
            <div
              class="flex items-center gap-2 cursor-pointer"
              style="font-size: var(--font-size-sm);"
              phx-click="show-preview"
              phx-value-port={@port}
            >
              <.spinner class="w-3 h-3" />
              <span style="color: var(--concocting);">starting dev server...</span>
            </div>
          <% @dev_server && @dev_server.status == :error -> %>
            <div style="font-size: var(--font-size-sm);">
              <span
                class="cursor-pointer"
                style="color: var(--error);"
                phx-click="show-preview"
                phx-value-port={@port || 0}
              >
                preview crashed
              </span>
              <span style="color: var(--border);">&nbsp;&middot;&nbsp;</span>
              <span class="action-text" phx-click={@start_event} phx-value-id={@target_id}>
                restart
              </span>
            </div>
          <% @has_config -> %>
            <div style="font-size: var(--font-size-sm);">
              <span class="action-text" phx-click={@start_event} phx-value-id={@target_id}>
                p start preview
              </span>
            </div>
          <% true -> %>
            <div style="font-size: var(--font-size-sm);">
              <div style="color: var(--muted); margin-bottom: 6px;">
                no <span style="color: var(--text);">.apothecary/preview.yml</span> found
              </div>
              <div class="oracle-code-block" style="font-size: var(--font-size-xs);">
                <pre><code style="color: var(--dim);">{"# .apothecary/preview.yml\ncommand: \"npm run dev\"\nport_count: 1\n# optional:\n# setup: \"npm install\"\n# base_port: 3000"}</code></pre>
              </div>
              <div style="color: var(--muted); font-size: var(--font-size-xs); margin-top: 4px;">
                add this file to your project root to enable live preview
              </div>
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
  attr :agents, :list, default: []
  attr :dev_server, :any, default: nil
  attr :has_preview_config, :boolean, default: false
  attr :project_id, :string, default: nil
  attr :editing_setting, :atom, default: nil
  attr :show_preview_help, :boolean, default: false

  def settings_line(assigns) do
    brewing? = assigns.swarm_status == :running
    any_working? = Enum.any?(assigns.agents, fn a -> a.status == :working end)
    any_unsandboxed = Enum.any?(assigns.agents, fn a -> a.status == :working && !a.sandboxed end)

    assigns =
      assigns
      |> assign(:brewing?, brewing?)
      |> assign(:any_working?, any_working?)
      |> assign(:any_unsandboxed, any_unsandboxed)

    ~H"""
    <div class="px-3 py-2" style="font-size: var(--font-size-xs);">
      <div class="flex items-center flex-wrap">
        <%!-- Brewer pill --%>
        <button
          phx-click={if @brewing?, do: "stop-swarm", else: "start-swarm"}
          class="cursor-pointer inline-flex items-center gap-1"
          style={"border: 1px solid #{if @brewing?, do: "var(--concocting)", else: "var(--border)"}; border-radius: 4px; padding: 2px 8px;"}
        >
          <span style={"color: #{cond do
            @brewing? && @any_working? -> "var(--concocting)"
            @brewing? -> "var(--text)"
            true -> "var(--muted)"
          end};"}>
            <%= if @brewing? && @any_working? do %>
              <.braille_spinner id="brew-spinner" offset={0} />
            <% else %>
              &#x2847;
            <% end %>
          </span>
          <span style={"color: #{if @brewing?, do: "var(--text)", else: "var(--muted)"}; font-weight: 600;"}>
            {@target_count}
          </span>
          <span style={"color: #{if @brewing?, do: "var(--dim)", else: "var(--muted)"};"}>
            brewers
          </span>
        </button>
        <%!-- +/- controls outside pill --%>
        <%= if @editing_setting == :brewers do %>
          <span class="inline-flex items-center gap-1 ml-1">
            <button phx-click="decrement-brewers" class="cursor-pointer" style="color: var(--accent);">
              &minus;
            </button>
            <button phx-click="increment-brewers" class="cursor-pointer" style="color: var(--accent);">
              +
            </button>
            <button phx-click="confirm-setting" class="cursor-pointer" style="color: var(--muted);">
              &#x2713;
            </button>
          </span>
        <% else %>
          <button
            phx-click="edit-setting"
            phx-value-setting="brewers"
            class="cursor-pointer ml-1"
            style="color: var(--muted);"
            title="Adjust brewer count"
          >
            &#x25B4;&#x25BE;
          </button>
        <% end %>
        <%!-- Stopped label --%>
        <span :if={!@brewing?} style="color: var(--muted); margin-left: 8px;">stopped</span>
        <span
          :if={@any_unsandboxed}
          style="color: var(--error); font-weight: 500; margin-left: 4px;"
          title="Brewers are running without OS-level sandbox."
        >
          unsandboxed
        </span>

        <%!-- Auto-PR --%>
        <span style="color: var(--border); margin: 0 6px;">&middot;</span>
        <span style="color: var(--dim);">t</span>&nbsp;
        <span style="color: var(--dim);">auto-pr</span>
        <button
          phx-click="toggle-auto-pr"
          class="cursor-pointer settings-value"
          style={"color: #{if @auto_pr, do: "var(--accent)", else: "var(--muted)"}; font-weight: 500;"}
        >
          &nbsp;{if @auto_pr, do: "on", else: "off"}
        </button>

        <%!-- Preview — pushed to far right --%>
        <span class="ml-auto flex items-center">
          <.preview_controls
            dev_server={@dev_server}
            has_config={@has_preview_config}
            target_id={@project_id || "project"}
            start_event="start-project-dev"
            stop_event="stop-project-dev"
            inline={true}
          />
        </span>
      </div>

      <%!-- Preview help expandable --%>
      <%= if @show_preview_help do %>
        <div class="mt-2" style="border-top: 1px solid var(--border); padding-top: 8px;">
          <div class="flex items-center justify-between mb-1">
            <span style="color: var(--text); font-weight: 500;">preview setup</span>
            <button
              phx-click="toggle-preview-help"
              class="cursor-pointer"
              style="color: var(--muted);"
            >
              &#x2715;
            </button>
          </div>
          <div style="color: var(--muted); margin-bottom: 6px;">
            add <span style="color: var(--text);">.apothecary/preview.yml</span>
            to your project root to spin up a dev server for main and each worktree:
          </div>
          <div class="oracle-code-block" style="font-size: var(--font-size-xs);">
            <pre><code style="color: var(--dim);">{"# .apothecary/preview.yml\ncommand: \"npm run dev\"\nport_count: 1\n# optional:\n# setup: \"npm install\"\n# base_port: 3000"}</code></pre>
          </div>
          <div style="color: var(--muted); margin-top: 4px;">
            each running worktree gets its own port
          </div>
        </div>
      <% end %>
    </div>
    """
  end

  # ── Worktree Input ─────────────────────────────────────

  attr :input_focused, :boolean, default: false
  attr :input_highlighted, :boolean, default: false
  attr :adding_task_to, :string, default: nil

  def worktree_input(assigns) do
    ~H"""
    <div class="px-3 py-2">
      <%= if @adding_task_to do %>
        <%!-- Task-add mode: single-line input with worktree prefix --%>
        <div
          class="relative rounded-lg transition-all duration-150"
          style="border: 1px solid color-mix(in srgb, var(--accent) 50%, transparent); background: color-mix(in srgb, var(--accent) 5%, var(--surface));"
        >
          <div class="flex items-center gap-2 px-3 py-2">
            <span style="color: var(--dim); font-size: var(--font-size-xs); white-space: nowrap; user-select: none;">
              <kbd style="color: var(--muted); font-size: var(--font-size-xxs); padding: 1px 4px; border: 1px solid var(--border); border-radius: 3px;">
                a
              </kbd>
              add task to
            </span>
            <span style="color: var(--accent); font-weight: 600; font-size: var(--font-size-sm); white-space: nowrap;">
              {@adding_task_to}
            </span>
            <input
              id="primary-input"
              type="text"
              phx-hook="TaskAddInput"
              phx-focus="input-focus"
              phx-blur="input-blur"
              autocomplete="off"
              class="flex-1 bg-transparent outline-none"
              style="color: var(--text); font-size: var(--font-size-sm); border: none; min-width: 0;"
              placeholder=""
              data-wt-id={@adding_task_to}
            />
          </div>
        </div>
      <% else %>
        <%!-- Normal mode: textarea for worktree creation --%>
        <div class="relative rounded-lg transition-all duration-150">
          <textarea
            id="primary-input"
            rows="4"
            phx-hook="TextareaSubmit"
            phx-focus="input-focus"
            phx-blur="input-blur"
            autocomplete="off"
            class="moonlight-input w-full resize-none"
            style={"min-height: 96px; max-height: 200px;#{if @input_highlighted && !@input_focused, do: " border-color: var(--dim);", else: ""}"}
            placeholder={
              if @input_highlighted && !@input_focused, do: "Press Enter or c to type...", else: ""
            }
          ></textarea>
          <div
            id="file-autocomplete-dropdown"
            phx-update="ignore"
            class="hidden fixed max-h-48 overflow-y-auto"
            style="background: var(--surface); border: 1px solid var(--border); z-index: 9999;"
          >
          </div>
          <button
            id="primary-input-send"
            phx-hook=".TextareaSend"
            type="button"
            class="absolute right-2 bottom-2 cursor-pointer p-1"
            style="color: var(--muted);"
            title="Send (Enter)"
          >
            <svg
              xmlns="http://www.w3.org/2000/svg"
              viewBox="0 0 20 20"
              fill="currentColor"
              class="w-4 h-4"
            >
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
          describe a worktree, or ? to ask
        </div>
      <% end %>
    </div>
    """
  end

  # ── Chat Input (bottom of left panel) ─────────────────

  attr :input_focused, :boolean, default: false
  attr :selected_card_id, :string, default: nil
  attr :adding_task_to, :string, default: nil
  attr :working_agent, :map, default: nil
  attr :worktree_mode, :boolean, default: false

  def chat_input(assigns) do
    # Determine current input mode for placeholder and badge
    {mode, mode_color, placeholder} =
      cond do
        assigns.worktree_mode ->
          {"worktree", "var(--reviewing)", "worktree name · esc cancel"}

        assigns.adding_task_to ->
          {"task", "var(--queued)", "add task to queue · ?question · esc cancel"}

        assigns.working_agent ->
          {"chat", "var(--concocting)", "message brewer · ?question · +task to queue"}

        assigns.selected_card_id ->
          {"task", "var(--queued)", "task to queue · ?question to ask"}

        true ->
          {nil, nil, "b new worktree · select a worktree to add tasks"}
      end

    assigns =
      assigns
      |> assign(:mode, mode)
      |> assign(:mode_color, mode_color)
      |> assign(:placeholder, placeholder)

    ~H"""
    <div
      style="border-top: 1px solid var(--border); background: var(--bg);"
      class="px-3 py-2 flex-shrink-0"
    >
      <div
        id="chat-image-previews"
        phx-update="ignore"
        style="display: none; gap: 6px; padding-bottom: 6px; flex-wrap: wrap; align-items: center;"
      >
      </div>
      <div class="flex items-center gap-2">
        <span
          :if={@mode}
          id="input-mode-badge"
          style={"background: color-mix(in srgb, #{@mode_color} 20%, var(--surface)); color: #{@mode_color}; font-size: var(--font-size-xxs); padding: 2px 6px; border-radius: 4px; font-weight: 600; white-space: nowrap;"}
          data-server-mode={@mode}
          data-server-color={@mode_color}
        >
          {@mode}
        </span>
        <input
          id="primary-input"
          type="text"
          phx-hook="ChatBottomInput"
          phx-focus="input-focus"
          phx-blur="input-blur"
          autocomplete="off"
          class="chat-bottom-input"
          placeholder={@placeholder}
          data-wt-id={@selected_card_id}
          data-refocus={if @adding_task_to, do: "true", else: "false"}
          data-server-mode={@mode}
        />
        <span style="color: var(--muted); font-size: var(--font-size-xs);">/</span>
      </div>
      <div
        id="file-autocomplete-dropdown"
        phx-update="ignore"
        class="hidden fixed max-h-48 overflow-y-auto"
        style="background: var(--surface); border: 1px solid var(--border); z-index: 9999;"
      >
      </div>
    </div>
    """
  end

  # ── Worktree Tree ──────────────────────────────────────

  attr :worktrees_by_status, :map, required: true
  attr :agents, :list, default: []
  attr :dev_servers, :map, default: %{}
  attr :selected_card, :integer, default: 0
  attr :card_ids, :list, default: []
  attr :collapsed_done, :boolean, default: true
  attr :collapsed_discarded, :boolean, default: true
  attr :adding_task_to, :string, default: nil
  attr :search_mode, :boolean, default: false
  attr :search_query, :string, default: ""
  attr :questions, :list, default: []

  def worktree_tree(assigns) do
    # Map status groups to display categories
    running = assigns.worktrees_by_status["running"] || []
    pr = assigns.worktrees_by_status["pr"] || []
    ready = assigns.worktrees_by_status["ready"] || []
    blocked = assigns.worktrees_by_status["blocked"] || []
    done = assigns.worktrees_by_status["done"] || []
    discarded = assigns.worktrees_by_status["discarded"] || []

    brewing = running
    assaying = pr
    queued = ready ++ blocked
    bottled = done

    # Apply search filter
    query = String.downcase(assigns.search_query || "")

    {brewing, assaying, queued, bottled, discarded} =
      if query != "" do
        f = fn entries ->
          Enum.filter(entries, fn e ->
            title = (e.worktree.title || e.worktree.id) |> String.downcase()
            String.contains?(title, query)
          end)
        end

        {f.(brewing), f.(assaying), f.(queued), f.(bottled), f.(discarded)}
      else
        {brewing, assaying, queued, bottled, discarded}
      end

    # Build question entries in tree_group format
    filtered_questions =
      assigns.questions
      |> Enum.sort_by(fn q -> q.created_at || "" end, :desc)
      |> then(fn qs ->
        if query != "" do
          Enum.filter(qs, fn q ->
            title = (q.title || q.id) |> String.downcase()
            String.contains?(title, query)
          end)
        else
          qs
        end
      end)

    # Only show root questions (not follow-ups) in the tree
    root_questions =
      Enum.filter(filtered_questions, fn q -> is_nil(q.parent_question_id) end)

    {pending_questions, answered_questions} =
      Enum.split_with(root_questions, fn q -> q.status in ["open", "in_progress"] end)

    pending_q_entries =
      Enum.map(pending_questions, fn q -> %{worktree: q, tasks: [], agent: nil, dev_server: nil} end)

    answered_q_entries =
      Enum.map(answered_questions, fn q -> %{worktree: q, tasks: [], agent: nil, dev_server: nil} end)

    assigns =
      assigns
      |> assign(:brewing, brewing)
      |> assign(:assaying, assaying)
      |> assign(:queued, queued)
      |> assign(:bottled, bottled)
      |> assign(:discarded, discarded)
      |> assign(:pending_q_entries, pending_q_entries)
      |> assign(:answered_q_entries, answered_q_entries)

    total_count =
      length(brewing) + length(assaying) + length(queued) + length(bottled) + length(discarded)

    # Count idle agents
    idle_count =
      Enum.count(assigns.agents, fn a -> a.status in [:idle, :starting] end)

    assigns =
      assigns
      |> assign(:total_count, total_count)
      |> assign(:idle_count, idle_count)

    ~H"""
    <div class="px-3 py-1">
      <%!-- Summary line --%>
      <div
        class="flex items-center gap-1 mb-2 px-1"
        style="font-size: var(--font-size-xs);"
      >
        <span :if={@brewing != []} style="color: var(--concocting); font-weight: 600;">
          {length(@brewing)} brewing
        </span>
        <span :if={@assaying != []} style="color: var(--assaying); font-weight: 600;">
          {length(@assaying)} reviewing
        </span>
        <span style="color: var(--muted);">
          <span :if={@brewing != [] || @assaying != []}>&middot; </span>{@total_count} total
        </span>
        <span :if={@idle_count > 0} style="color: var(--muted);">
          &middot; {@idle_count} idle
        </span>
        <span :if={@total_count > 0} class="ml-auto" style="color: var(--muted);">
          1-{@total_count}
        </span>
      </div>

      <div style="border-top: 1px solid var(--border); margin: 4px 0 6px;" />

      <%!-- Brewing group --%>
      <.tree_group
        :if={@brewing != []}
        label="brewing"
        count={length(@brewing)}
        color="var(--concocting)"
        entries={@brewing}
        dot="●"
        dot_class="dot-pulse"
        title_color="var(--text)"
        card_ids={@card_ids}
        selected_card={@selected_card}
        adding_task_to={@adding_task_to}
        animated_header_dot={true}
      />

      <%!-- Reviewing group --%>
      <.tree_group
        :if={@assaying != []}
        label="reviewing"
        count={length(@assaying)}
        color="var(--assaying)"
        entries={@assaying}
        dot="◎"
        dot_class=""
        title_color="var(--dim)"
        card_ids={@card_ids}
        selected_card={@selected_card}
        status_label="awaiting review"
        adding_task_to={@adding_task_to}
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
        title_color="var(--muted)"
        opacity="1"
        card_ids={@card_ids}
        selected_card={@selected_card}
        adding_task_to={@adding_task_to}
      />

      <%!-- Bottled group (collapsed by default) --%>
      <%= if @bottled != [] do %>
        <div
          class="cursor-pointer py-1 px-1"
          phx-click="toggle-done-collapse"
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
          adding_task_to={@adding_task_to}
        />
      <% end %>

      <%!-- Discarded group (collapsed by default) --%>
      <%= if @discarded != [] do %>
        <div
          class="cursor-pointer py-1 px-1"
          phx-click="toggle-discarded-collapse"
          style="font-size: var(--font-size-sm);"
        >
          <span style="color: var(--dim);">
            {if @collapsed_discarded, do: "▸", else: "▾"} discarded ({length(@discarded)})
          </span>
        </div>
        <.tree_group
          :if={!@collapsed_discarded}
          label={nil}
          count={0}
          color="var(--dim)"
          entries={@discarded}
          dot="✕"
          dot_class=""
          title_color="var(--dim)"
          card_ids={@card_ids}
          selected_card={@selected_card}
          adding_task_to={@adding_task_to}
        />
      <% end %>

      <%!-- Questions group --%>
      <%= if @pending_q_entries != [] || @answered_q_entries != [] do %>
        <div style="border-top: 1px solid var(--border); margin: 6px 0;" />
        <%!-- Pending questions (thinking) --%>
        <.tree_group
          :if={@pending_q_entries != []}
          label="questions"
          count={length(@pending_q_entries)}
          color="var(--accent)"
          entries={@pending_q_entries}
          dot="?"
          dot_class="dot-pulse"
          title_color="var(--text)"
          card_ids={@card_ids}
          selected_card={@selected_card}
          adding_task_to={@adding_task_to}
          animated_header_dot={true}
        />
        <%!-- Answered questions --%>
        <.tree_group
          :if={@answered_q_entries != []}
          label={if @pending_q_entries == [], do: "questions", else: nil}
          count={if @pending_q_entries == [], do: length(@answered_q_entries), else: 0}
          color="var(--dim)"
          entries={@answered_q_entries}
          dot="?"
          dot_class=""
          title_color="var(--dim)"
          card_ids={@card_ids}
          selected_card={@selected_card}
          adding_task_to={@adding_task_to}
        />
      <% end %>

      <%!-- Empty state --%>
      <div
        :if={@brewing == [] && @assaying == [] && @queued == [] && @bottled == [] && @discarded == [] && @pending_q_entries == [] && @answered_q_entries == []}
        class="py-6"
        style="color: var(--muted); font-size: var(--font-size-sm);"
      >
        no worktrees yet
      </div>
    </div>
    """
  end

  # Tree group component — compact card list for worktree panel
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
  attr :adding_task_to, :string, default: nil
  attr :animated_header_dot, :boolean, default: false

  defp tree_group(assigns) do
    ~H"""
    <div style={"opacity: #{@opacity};"}>
      <div style="font-size: var(--font-size-sm);">
        <%= for {entry, _idx} <- Enum.with_index(@entries) do %>
          <% wt = entry.worktree
          selected? = selected_entry?(@card_ids, @selected_card, wt.id)
          card_num = card_number(@card_ids, wt.id)
          tasks = entry.tasks
          done_count = Enum.count(tasks, &(&1.status in ["done", "closed"]))
          total_count = length(tasks) %>
          <div
            class={"worktree-card #{if selected?, do: "worktree-card--selected"}"}
            style={
              if selected?,
                do: "border-left: 2px solid #{@color};",
                else: "border-left: 2px solid transparent;"
            }
            phx-click="select-task"
            phx-value-id={wt.id}
            data-card-id={wt.id}
            data-selected={if(selected?, do: "true")}
          >
            <div class="flex items-center gap-1.5">
              <%!-- Status dot --%>
              <%= if @animated_header_dot && entry.agent do %>
                <span style={"color: #{@color}; flex-shrink: 0;"}>
                  <.braille_spinner id={"wt-spin-#{wt.id}"} offset={card_num * 3} />
                </span>
              <% else %>
                <span class={@dot_class} style={"color: #{@color}; flex-shrink: 0;"}>{@dot}</span>
              <% end %>
              <%!-- Card number --%>
              <span style="color: var(--muted); font-size: var(--font-size-xs); min-width: 12px;">
                {card_num}
              </span>
              <%!-- Worktree name --%>
              <span class="truncate" style={"color: #{@title_color}; font-weight: 500;"}>
                {wt.git_branch || wt.title || wt.id}
              </span>
              <%!-- Right side: progress ratio + blocks + arrow --%>
              <span
                class="ml-auto flex items-center gap-1.5 flex-shrink-0"
                style="font-size: var(--font-size-xs); color: var(--muted);"
              >
                <span :if={total_count > 0}>{done_count}/{total_count}</span>
                <span :if={total_count > 0} class="worktree-progress">
                  <%= for i <- 0..min(total_count - 1, 15) do %>
                    <span
                      class="worktree-progress-block"
                      style={"background: #{if i < done_count, do: @color, else: "var(--border)"}; opacity: #{if i < done_count, do: "1", else: "0.4"};"}
                    />
                  <% end %>
                </span>
              </span>
            </div>
          </div>
        <% end %>
      </div>
    </div>
    """
  end

  defp selected_entry?(card_ids, selected_card, wt_id) do
    case Enum.at(card_ids, selected_card) do
      ^wt_id -> true
      _ -> false
    end
  end

  defp card_number(card_ids, wt_id) do
    case Enum.find_index(card_ids, &(&1 == wt_id)) do
      nil -> 0
      idx -> idx + 1
    end
  end

  # ── Worktree Detail ────────────────────────────────────

  attr :task, :map, required: true
  attr :children, :list, default: []
  attr :editing_field, :atom, default: nil
  attr :working_agent, :map, default: nil
  attr :agent_output, :list, default: []
  attr :dev_server, :map, default: nil
  attr :has_preview_config, :boolean, default: false
  attr :pending_action, :any, default: nil
  attr :loading_action, :atom, default: nil
  attr :editing_child_id, :string, default: nil
  attr :worktree_questions, :list, default: []
  attr :follow_up_question_id, :string, default: nil
  attr :expanded_detail_items, :any, default: nil
  attr :branch_diff_stat, :any, default: nil

  def worktree_detail(assigns) do
    # Render question-specific view when kind is "question"
    if Map.get(assigns.task, :kind) == "question" do
      question_detail(assigns)
    else
      worktree_detail_inner(assigns)
    end
  end

  defp question_detail(assigns) do
    answer = question_answer(assigns.task)
    time_ago = format_relative_time(assigns.task.created_at)
    is_thinking = assigns.task.status in ["open", "in_progress"]

    assigns =
      assigns
      |> assign(:answer, answer)
      |> assign(:time_ago, time_ago)
      |> assign(:is_thinking, is_thinking)

    ~H"""
    <div class="px-4 py-4 scroll-main overflow-y-auto flex-1">
      <%!-- Question title --%>
      <div class="mb-4">
        <div class="flex items-start justify-between">
          <div class="flex-1 min-w-0">
            <div class="flex items-center gap-2">
              <span style="color: var(--accent); font-weight: 600; font-size: var(--font-size-title);">?</span>
              <span style="font-size: var(--font-size-title); font-weight: 600; color: var(--text);">
                {@task.title}
              </span>
            </div>
            <div
              class="flex items-center gap-1 mt-1"
              style="font-size: var(--font-size-xs); color: var(--muted);"
            >
              <span>{@task.id}</span>
              <span :if={@time_ago}>&middot; {@time_ago}</span>
              <span :if={@task.status == "done"} style="color: var(--accent);">&middot; answered</span>
              <span :if={@is_thinking} style="color: var(--concocting);">&middot; thinking</span>
            </div>
          </div>
          <button
            phx-click="deselect-task"
            class="cursor-pointer flex-shrink-0"
            style="color: var(--muted); font-size: var(--font-size-xs);"
          >
            esc
          </button>
        </div>
      </div>

      <%!-- Answer --%>
      <%= if @answer != "" do %>
        <div
          id={"q-detail-answer-#{@task.id}"}
          class="px-3 py-3 question-answer"
          style={[
            "border-left: 2px solid color-mix(in srgb, var(--accent) 40%, transparent);",
            "background: color-mix(in srgb, var(--surface) 80%, transparent);",
            "border-radius: 0 6px 6px 0;",
            "font-size: var(--font-size-sm); color: var(--dim);",
            "white-space: pre-wrap; line-height: 1.6;"
          ]}
        >
          {@answer}
        </div>
        <div class="mt-2 flex items-center gap-2">
          <.copy_button target={"#q-detail-answer-#{@task.id}"} />
          <button
            phx-click="toggle-follow-up"
            phx-value-question-id={@task.id}
            style="color: var(--muted); font-size: var(--font-size-xs);"
            class="hover:underline cursor-pointer"
          >
            follow up
          </button>
        </div>
        <%!-- Follow-up input --%>
        <%= if @follow_up_question_id == @task.id do %>
          <form
            phx-submit="submit-follow-up"
            id={"follow-up-form-#{@task.id}"}
            class="mt-3 flex items-center gap-2 px-3 py-2"
            style="font-size: var(--font-size-sm); background: color-mix(in srgb, var(--accent) 8%, var(--bg)); border: 1px solid color-mix(in srgb, var(--accent) 25%, transparent); border-radius: 6px;"
          >
            <input type="hidden" name="parent_question_id" value={@task.id} />
            <span style="color: var(--accent); font-weight: 600;">?</span>
            <input
              type="text"
              name="follow_up_text"
              placeholder="follow-up question..."
              autofocus
              class="flex-1 bg-transparent outline-none"
              style="color: var(--text); border: none; padding: 2px 0; font-size: var(--font-size-sm);"
            />
            <span style="color: var(--muted); font-size: var(--font-size-xs);">
              enter &middot; esc close
            </span>
          </form>
        <% end %>
      <% else %>
        <%!-- Thinking state --%>
        <div
          :if={@is_thinking}
          class="pl-3 flex items-center gap-2 py-4"
          style="border-left: 2px solid color-mix(in srgb, var(--accent) 40%, transparent); font-size: var(--font-size-sm); color: var(--muted);"
        >
          <.braille_spinner id={"q-detail-spin-#{@task.id}"} offset={0} />
          <span>thinking...</span>
        </div>
      <% end %>

      <%!-- Follow-up questions thread --%>
      <% grouped = group_questions_threaded(@worktree_questions) %>
      <div :if={grouped != []} class="mt-6">
        <div style="border-top: 1px solid var(--border); padding-top: 16px; margin-bottom: 8px;" />
        <div :for={thread <- grouped} class="mb-4">
          <.question_thread_item
            :for={q <- thread}
            q={q}
            depth={q.__depth__ || 0}
            follow_up_id={@follow_up_question_id}
          />
        </div>
      </div>
    </div>
    """
  end

  defp worktree_detail_inner(assigns) do
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

    # Compute task progress
    done_children = Enum.count(assigns.children, fn c -> c.status in ["done", "closed"] end)
    total_children = length(assigns.children)

    # Git branch name
    git_branch = Map.get(assigns.task, :git_branch, nil)

    # Dev server port
    dev_port =
      case assigns.dev_server do
        %{ports: [%{port: p} | _], status: :running} -> p
        _ -> nil
      end

    # Split children into done, active (in_progress), and pending
    done_tasks = Enum.filter(assigns.children, fn c -> c.status in ["done", "closed"] end)
    active_task = Enum.find(assigns.children, fn c -> c.status == "in_progress" end)

    pending_tasks =
      Enum.filter(assigns.children, fn c ->
        c.status not in ["done", "closed", "in_progress"]
      end)

    # Root questions for inline display (not follow-ups)
    root_questions =
      Enum.filter(assigns.worktree_questions, fn q ->
        is_nil(Map.get(q, :parent_question_id))
      end)

    expanded = assigns.expanded_detail_items || MapSet.new()

    assigns =
      assigns
      |> assign(:done_children, done_children)
      |> assign(:total_children, total_children)
      |> assign(:git_branch, git_branch)
      |> assign(:dev_port, dev_port)
      |> assign(:done_tasks, done_tasks)
      |> assign(:active_task, active_task)
      |> assign(:pending_tasks, pending_tasks)
      |> assign(:root_questions, root_questions)
      |> assign(:expanded, expanded)

    ~H"""
    <div class="px-4 py-4 scroll-main overflow-y-auto flex-1">
      <%!-- 1. Title + Status --%>
      <div class="mb-3">
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
                  style="font-size: var(--font-size-title); font-weight: 600;"
                />
                <div class="flex items-center gap-2 mt-1">
                  <button type="submit" class="action-pill">save</button>
                  <button type="button" phx-click="cancel-edit" class="action-text">cancel</button>
                </div>
              </.form>
            <% else %>
              <div class="flex items-center gap-2">
                <span style={"color: #{@status_color};"}>
                  <%= if @status_group == "brewing" do %>
                    <.braille_spinner id="detail-title-spin" offset={0} />
                  <% else %>
                    {@status_dot}
                  <% end %>
                </span>
                <span
                  phx-click="start-edit"
                  phx-value-field="title"
                  class="cursor-pointer"
                  style="font-size: var(--font-size-title); font-weight: 600; color: var(--text);"
                >
                  {@task.title}
                </span>
              </div>
            <% end %>
            <%!-- Metadata line --%>
            <div
              class="flex items-center gap-1 mt-1 flex-wrap"
              style="font-size: var(--font-size-xs); color: var(--muted);"
            >
              <span>{@task.id}</span>
              <span :if={@git_branch}>
                &middot; <span style="color: var(--dim);">{@git_branch}</span>
              </span>
              <span :if={@brewer_label}>
                &middot; <span style="color: var(--dim);">{@brewer_label}</span>
              </span>
              <span :if={@time_ago}>&middot; {@time_ago}</span>
              <span
                :if={@dev_port}
                class="cursor-pointer"
                style="color: var(--accent);"
                phx-click="show-preview"
                phx-value-port={@dev_port}
              >
                &middot; :{@dev_port} &#x2197;
              </span>
              <span
                :if={@working_agent && @working_agent.status == :working && !@working_agent.sandboxed}
                style="color: var(--error); font-weight: 500;"
              >
                &middot; unsandboxed
              </span>
            </div>
          </div>
          <button
            phx-click="deselect-task"
            class="cursor-pointer flex-shrink-0"
            style="color: var(--muted); font-size: var(--font-size-xs);"
          >
            esc
          </button>
        </div>
      </div>

      <%!-- 2. Progress bar --%>
      <div :if={@total_children > 0} class="mb-1">
        <div class="flex items-center gap-2">
          <div
            class="flex-1 rounded-full overflow-hidden"
            style="height: 4px; background: var(--border);"
          >
            <div style={"width: #{if @total_children > 0, do: round(@done_children / @total_children * 100), else: 0}%; height: 100%; background: var(--concocting); border-radius: 9999px; transition: width 0.3s ease;"} />
          </div>
          <span style="font-size: var(--font-size-xs); color: var(--muted); flex-shrink: 0;">
            {@done_children}/{@total_children}
          </span>
        </div>
      </div>

      <%!-- 3. Done tasks summary --%>
      <div
        :if={@done_children > 0}
        class="mb-1"
        style="font-size: var(--font-size-xs); color: var(--dim);"
      >
        <span style="color: var(--accent);">&#x25CF;</span>
        {@done_children} done
      </div>

      <%!-- 4. Done tasks — expandable rows --%>
      <div :if={@done_tasks != []} class="mb-1" style="font-size: var(--font-size-sm);">
        <div :for={task <- @done_tasks}>
          <div
            class="flex items-center gap-2 py-0.5 cursor-pointer group"
            phx-click="toggle-detail-expand"
            phx-value-id={task.id}
          >
            <span style="color: var(--accent);">✓</span>
            <span style="color: var(--muted);">{task.title}</span>
            <span
              class="ml-auto opacity-0 group-hover:opacity-100 transition-opacity"
              style="font-size: var(--font-size-xxs); color: var(--dim);"
            >
              {if MapSet.member?(@expanded, task.id), do: "▾", else: "▸"}
            </span>
          </div>
          <%!-- Expanded content for done task --%>
          <div
            :if={MapSet.member?(@expanded, task.id)}
            class="ml-6 mb-2 mt-1"
          >
            <%!-- Task notes --%>
            <div
              :if={task.notes && task.notes != ""}
              class="px-2 py-1"
              style="border-left: 2px solid var(--border); font-size: var(--font-size-xs); color: var(--muted); white-space: pre-wrap; line-height: 1.5;"
            >
              {task.notes}
            </div>
            <div
              :if={is_nil(task.notes) || task.notes == ""}
              style="font-size: var(--font-size-xs); color: var(--dim);"
            >
              no notes
            </div>
          </div>
        </div>
      </div>

      <%!-- Inline questions (answered, expandable) --%>
      <div
        :if={Enum.any?(@root_questions, fn q -> q.status not in ["open", "in_progress"] end)}
        class="mb-1"
        style="font-size: var(--font-size-sm);"
      >
        <%= for q <- Enum.filter(@root_questions, fn q -> q.status not in ["open", "in_progress"] end) do %>
          <% answer = question_answer(q) %>
          <% follow_ups = Enum.count(@worktree_questions, fn fq -> Map.get(fq, :parent_question_id) == q.id end) %>
          <div
            class="flex items-center gap-2 py-0.5 cursor-pointer group"
            phx-click="toggle-detail-expand"
            phx-value-id={q.id}
          >
            <span style="color: var(--accent); font-weight: 600;">?</span>
            <span style="color: var(--muted);" class="truncate">{q.title}</span>
            <span
              :if={follow_ups > 0}
              class="ml-auto flex-shrink-0"
              style="font-size: var(--font-size-xxs); color: var(--dim);"
            >
              &middot; {follow_ups + 1} msgs
            </span>
          </div>
          <%!-- Expanded question answer --%>
          <div
            :if={MapSet.member?(@expanded, q.id)}
            class="ml-6 mb-2 mt-1"
          >
            <%= if answer != "" do %>
              <div
                id={"q-inline-answer-#{q.id}"}
                class="px-2 py-1"
                style="border-left: 2px solid color-mix(in srgb, var(--accent) 40%, transparent); font-size: var(--font-size-xs); color: var(--dim); white-space: pre-wrap; line-height: 1.5;"
              >
                {answer}
              </div>
              <div class="mt-1 flex items-center gap-2">
                <button
                  phx-click="toggle-follow-up"
                  phx-value-question-id={q.id}
                  style="color: var(--muted); font-size: var(--font-size-xs);"
                  class="hover:underline cursor-pointer"
                >
                  follow up
                </button>
              </div>
              <%!-- Follow-up input --%>
              <%= if @follow_up_question_id == q.id do %>
                <form
                  phx-submit="submit-follow-up"
                  id={"follow-up-form-inline-#{q.id}"}
                  class="mt-2 flex items-center gap-2 px-2 py-1"
                  style="font-size: var(--font-size-xs); background: color-mix(in srgb, var(--accent) 8%, var(--bg)); border: 1px solid color-mix(in srgb, var(--accent) 25%, transparent); border-radius: 6px;"
                >
                  <input type="hidden" name="parent_question_id" value={q.id} />
                  <span style="color: var(--accent); font-weight: 600;">?</span>
                  <input
                    type="text"
                    name="follow_up_text"
                    placeholder="follow-up..."
                    autofocus
                    class="flex-1 bg-transparent outline-none"
                    style="color: var(--text); border: none; padding: 2px 0; font-size: var(--font-size-xs);"
                  />
                  <span style="color: var(--muted); font-size: var(--font-size-xxs);">
                    enter
                  </span>
                </form>
              <% end %>
            <% else %>
              <div style="font-size: var(--font-size-xs); color: var(--dim);">
                no answer yet
              </div>
            <% end %>
          </div>
        <% end %>
      </div>

      <%!-- 5. Active task (highlighted) --%>
      <div :if={@active_task} class="detail-active-task mb-1">
        <div class="flex items-center gap-2">
          <span style="color: var(--concocting);">
            <.braille_spinner id="detail-active-task-spin" offset={2} />
          </span>
          <span style="color: var(--text); font-weight: 500; font-size: var(--font-size-sm);">
            {@active_task.title}
          </span>
          <span
            :if={@brewer_label}
            class="ml-auto"
            style="color: var(--muted); font-size: var(--font-size-xxs);"
          >
            {@brewer_label}
          </span>
        </div>
      </div>

      <%!-- Inline questions (pending/thinking) --%>
      <div
        :if={Enum.any?(@root_questions, fn q -> q.status in ["open", "in_progress"] end)}
        class="mb-1"
        style="font-size: var(--font-size-sm);"
      >
        <%= for q <- Enum.filter(@root_questions, fn q -> q.status in ["open", "in_progress"] end) do %>
          <div class="flex items-center gap-2 py-0.5">
            <span style="color: var(--accent); font-weight: 600;">?</span>
            <span style="color: var(--text);">{q.title}</span>
            <span
              class="ml-auto flex-shrink-0"
              style="font-size: var(--font-size-xxs); color: var(--concocting);"
            >
              <.braille_spinner id={"q-inline-spin-#{q.id}"} offset={0} />
            </span>
          </div>
        <% end %>
      </div>

      <%!-- 6. Queued tasks — tree chars --%>
      <div :if={@pending_tasks != []} class="mb-2" style="font-size: var(--font-size-sm);">
        <%= for {child, idx} <- Enum.with_index(@pending_tasks) do %>
          <% is_last = idx == length(@pending_tasks) - 1 %>
          <div class="flex items-center gap-2 py-0.5">
            <span style="color: var(--border); font-family: monospace; font-size: var(--font-size-xs); width: 16px; text-align: center; flex-shrink: 0;">
              {if is_last, do: "└─", else: "├─"}
            </span>
            <span style="color: var(--muted);">○</span>
            <span style="color: var(--muted);">{child.title}</span>
          </div>
        <% end %>
      </div>

      <%!-- Merge conflict auto-fix warning --%>
      <% merge_fix_tasks =
        Enum.filter(@children, fn c ->
          String.contains?(c.title || "", "merge conflict")
        end) %>
      <details
        :if={merge_fix_tasks != []}
        class="mb-4 rounded"
        style="background: color-mix(in srgb, var(--concocting) 12%, transparent); border: 1px solid color-mix(in srgb, var(--concocting) 30%, transparent); font-size: var(--font-size-sm);"
      >
        <summary class="px-3 py-2 cursor-pointer select-none list-none flex items-center gap-1">
          <span
            class="merge-arrow inline-block transition-transform duration-150"
            style="font-size: 0.65em; color: var(--dim);"
          >
            ▶
          </span>
          <span style="color: var(--concocting); font-weight: 600;">
            &#x26A0; merge conflicts auto-fixed
          </span>
          <span style="color: var(--dim);">
            &mdash; review decisions
          </span>
        </summary>
        <div
          class="px-3 pb-2"
          style="color: var(--fg); border-top: 1px solid color-mix(in srgb, var(--concocting) 20%, transparent);"
        >
          <div :for={task <- merge_fix_tasks} class="mt-2">
            <div :if={task.notes && task.notes != ""}>
              <pre
                class="whitespace-pre-wrap break-words"
                style="font-size: var(--font-size-xs); color: var(--muted); line-height: 1.5; margin: 0;"
              >{task.notes}</pre>
            </div>
            <div
              :if={is_nil(task.notes) || task.notes == ""}
              style="color: var(--dim); font-size: var(--font-size-xs);"
            >
              No resolution notes recorded.
            </div>
          </div>
        </div>
      </details>

      <%!-- Branch diff stat (expandable) --%>
      <%= if is_map(@branch_diff_stat) and @branch_diff_stat.files != [] do %>
        <div class="mb-2">
          <div
            class="flex items-center gap-2 py-0.5 cursor-pointer"
            phx-click="toggle-detail-expand"
            phx-value-id="branch-diff-stat"
            style="font-size: var(--font-size-xs);"
          >
            <span style="color: var(--dim);">
              {if MapSet.member?(@expanded, "branch-diff-stat"), do: "▾", else: "▸"}
            </span>
            <span style="color: var(--dim);">
              {@branch_diff_stat.summary}
            </span>
          </div>
          <div
            :if={MapSet.member?(@expanded, "branch-diff-stat")}
            class="ml-4 mt-1"
            style="font-size: var(--font-size-xs);"
          >
            <div
              :for={file <- @branch_diff_stat.files}
              class="flex items-center gap-2 py-0.5"
              style="font-family: var(--font-mono, monospace);"
            >
              <span style="color: var(--dim);" class="truncate flex-1 min-w-0">{file.path}</span>
              <span style="color: var(--muted); flex-shrink: 0;">&vert; {file.count}</span>
              <span style="flex-shrink: 0;">
                <span :if={file.additions > 0} style="color: var(--accent);">{String.duplicate("+", min(file.additions, 20))}</span>
                <span :if={file.deletions > 0} style="color: var(--error);">{String.duplicate("-", min(file.deletions, 20))}</span>
              </span>
            </div>
          </div>
        </div>
      <% end %>

      <%!-- 7. Activity stream (agent output live, or notes as historical stream) --%>
      <%= if @agent_output != [] do %>
        <%!-- Live brewer stream --%>
        <div class="mb-4">
          <div
            class="mb-3"
            style="border-top: 1px solid var(--border); padding-top: 16px; margin-top: 12px;"
          >
            <span style="color: var(--muted); font-size: var(--font-size-xs);">
              &mdash; {@brewer_label || "brewer"} assigned to {String.slice(@task.id || "", 0..9)}
            </span>
          </div>
          <div
            id="agent-output-inline"
            class="detail-brewer-log"
            phx-hook="ScrollBottom"
          >
            <div :for={line <- Enum.take(@agent_output, -60)}>
              <.brewer_log_line line={line} />
            </div>
          </div>
          <div :if={@working_agent && @working_agent.status == :working} class="mt-1">
            <span style="color: var(--concocting); font-size: var(--font-size-sm);">
              <.braille_spinner id="detail-working-spin" offset={1} /> working...
            </span>
          </div>
        </div>
      <% else %>
        <%!-- Historical notes rendered as stream --%>
        <div :if={@task.notes && @task.notes != ""} class="mb-4">
          <div
            class="mb-3"
            style="border-top: 1px solid var(--border); padding-top: 16px; margin-top: 12px;"
          />
          <div
            id="task-notes-stream"
            class="detail-brewer-log"
          >
            <div :for={line <- String.split(@task.notes || "", "\n")}>
              <.brewer_log_line line={line} />
            </div>
          </div>
          <.copy_button target="#task-notes-stream" />
        </div>
      <% end %>

      <%!-- 7. Actions (only for merge/PR states) --%>
      <div
        :if={
          @loading? || @pending_action || @pr_url ||
            @task.status in ["brew_done", "done", "closed"] ||
            @has_preview_config || @dev_server
        }
        class="flex items-center gap-3 mb-4 flex-wrap"
        style="font-size: var(--font-size-sm);"
      >
        <%= if @loading? do %>
          <div class="flex items-center gap-2">
            <.spinner class="w-3 h-3" />
            <span style="color: var(--dim);">{loading_label(@loading_action)}</span>
          </div>
        <% else %>
          <%= if @pending_action do %>
            <span style="color: var(--concocting);">
              {cond do
                match?({:local_merge, _, _}, @pending_action) -> "merge locally (no PR)?"
                match?({:direct_merge, _, _}, @pending_action) -> "merge directly?"
                true -> "merge this PR?"
              end}
            </span>
            <button phx-click="confirm-merge" class="action-pill">confirm</button>
            <button phx-click="cancel-merge" class="action-text">cancel</button>
          <% else %>
            <%= if @task.status == "merged" do %>
              <span style="color: var(--bottled);">merged</span>
            <% end %>
            <%= if @task.status == "cancelled" do %>
              <span style="color: var(--dim);">discarded</span>
            <% end %>
            <%= if @task.status in ["brew_done", "done", "closed"] and is_nil(@pr_url) do %>
              <span class="action-pill" phx-click="promote-to-assaying">c create-pr</span>
              <span class="action-pill" phx-click="local-merge">g git-merge</span>
              <span class="action-pill" phx-click="show-diff">d diff</span>
              <span class="action-pill" phx-click="close-task">x close</span>
            <% end %>
            <span
              :if={@pr_url && @task.status not in ["merged", "cancelled"]}
              class="action-pill"
              phx-click="merge-pr"
            >
              m merge
            </span>
            <%!-- Preview button: start dev server + open preview panel --%>
            <%= cond do %>
              <% @dev_server && @dev_server.status == :running -> %>
                <span
                  class="action-pill"
                  phx-click="show-preview"
                  phx-value-port={@dev_port}
                >
                  p preview :{@dev_port}
                </span>
              <% @dev_server && @dev_server.status == :starting -> %>
                <span
                  class="action-pill"
                  style="color: var(--concocting);"
                  phx-click="show-preview"
                  phx-value-port={@dev_port}
                >
                  <.braille_spinner id="action-preview-spinner" offset={0} /> p preview starting...
                </span>
              <% @has_preview_config -> %>
                <span class="action-pill" phx-click="preview-worktree">p preview</span>
              <% true -> %>
            <% end %>
          <% end %>
        <% end %>
      </div>

      <%!-- 8. PR link --%>
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

      <%!-- 9. Description --%>
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
    </div>
    """
  end

  # Renders a single brewer output line with tool call styling
  defp brewer_log_line(assigns) do
    {line_type, tag, rest} = parse_log_line(assigns.line)
    assigns = assign(assigns, line_type: line_type, tag: tag, rest: rest)

    ~H"""
    <div style="font-size: var(--font-size-xs); line-height: 1.6;">
      <%= case @line_type do %>
        <% :tool -> %>
          <span style="color: var(--accent); font-weight: 600;">[{@tag}]</span>
          <span style="color: var(--text); font-weight: 500;">{@rest}</span>
        <% :user -> %>
          <span style="color: var(--queued); font-weight: 600;">▸ you:</span>
          <span style="color: var(--text); font-weight: 500;">{@rest}</span>
        <% :narrative -> %>
          <span style="color: var(--dim); font-weight: 500;">&mdash; {@rest}</span>
        <% :committed -> %>
          <span style="color: var(--accent);">{@rest}</span>
        <% _ -> %>
          <span style="color: var(--muted);">{@rest}</span>
      <% end %>
    </div>
    """
  end

  defp parse_log_line(line) do
    cond do
      # User message sent to brewer
      match = Regex.run(~r/^▸ you: (.*)$/, line) ->
        [_, rest] = match
        {:user, nil, rest}

      # Tool use: [tool: Bash] or [Bash] style
      match = Regex.run(~r/^\[tool: (.+?)\](.*)$/, line) ->
        [_, name, rest] = match
        {:tool, name, String.trim(rest)}

      match = Regex.run(~r/^\[([A-Z][A-Za-z]+)\]\s*(.*)$/, line) ->
        [_, name, rest] = match
        {:tool, name, String.trim(rest)}

      # Narrative: — or -- prefixed
      String.starts_with?(line, "—") or String.starts_with?(line, "-- ") ->
        {:narrative, nil,
         String.trim_leading(line, "—") |> String.trim_leading("-- ") |> String.trim()}

      # Timestamped notes: [2026-03-06 22:58:01] text
      match = Regex.run(~r/^\[\d{4}-\d{2}-\d{2}\s+\d{2}:\d{2}:\d{2}\]\s*(.*)$/, line) ->
        [_, rest] = match
        {:narrative, nil, rest}

      # Session markers
      Regex.match?(~r/^Session completed|^Branch pushed|^Commits? made/i, line) ->
        {:narrative, nil, line}

      # Commit lines (hash + message)
      Regex.match?(~r/^[0-9a-f]{7,}\s+/, line) ->
        {:committed, nil, line}

      String.starts_with?(String.downcase(line), "committed") or
          String.starts_with?(String.downcase(line), "commit") ->
        {:committed, nil, line}

      # Diff stat lines: file | count ++++---
      Regex.match?(~r/^.+\|\s+\d+\s*[+\-]+/, line) ->
        {:committed, nil, line}

      # Summary diff line: N files changed, N insertions(+), N deletions(-)
      Regex.match?(~r/^\d+ files? changed/, line) ->
        {:committed, nil, line}

      # File path lines (src/foo.tsx, lib/bar.ex, etc.)
      Regex.match?(~r/^(src|lib|test|assets|config)\/\S+/, line) ->
        {:committed, nil, line}

      # PASS/FAIL test results
      Regex.match?(~r/^(PASS|FAIL|OK)\s/, line) ->
        {:committed, nil, line}

      true ->
        {:text, nil, line}
    end
  end

  # ── Preview Panel (unified preview with source switcher) ─

  @doc """
  Full-panel preview with source switcher bar.
  Shows all available preview sources (main project + worktrees with running dev servers).
  """
  attr :port, :integer, default: nil
  attr :dev_servers, :map, default: %{}
  attr :current_project, :map, default: nil
  attr :show_logs, :boolean, default: false
  attr :worktrees_by_status, :map, default: %{}

  def preview_panel(assigns) do
    # Build list of all available preview sources
    project_id = assigns.current_project && assigns.current_project.id

    # Build a lookup from worktree id to worktree for branch name display
    wt_lookup =
      assigns.worktrees_by_status
      |> Enum.flat_map(fn {_status, groups} ->
        Enum.map(groups, fn g -> {g.worktree.id, g.worktree} end)
      end)
      |> Map.new()

    # Build sources: expand each dev server's ports into separate entries
    main_sources =
      case assigns.dev_servers[project_id] do
        %{ports: ports, status: s} when s in [:running, :starting, :error] and is_list(ports) ->
          Enum.map(ports, fn %{port: p, name: name} ->
            label = if length(ports) > 1, do: "main:#{name}", else: "main"
            %{id: project_id, label: label, port: p}
          end)

        _ ->
          []
      end

    wt_sources =
      assigns.dev_servers
      |> Enum.filter(fn {id, server} ->
        id != project_id and
          match?(%{status: s, ports: [_ | _]} when s in [:running, :starting, :error], server)
      end)
      |> Enum.flat_map(fn {id, %{ports: ports}} ->
        wt = Map.get(wt_lookup, id)
        branch = (wt && wt.git_branch) || (wt && wt.title)

        short_label =
          if branch,
            do: branch |> String.replace_leading("worktree/", ""),
            else: id |> to_string() |> String.replace_leading("wt-", "") |> String.slice(0, 6)

        Enum.map(ports, fn %{port: p, name: name} ->
          label = if length(ports) > 1, do: "#{short_label}:#{name}", else: short_label
          %{id: id, label: label, port: p}
        end)
      end)
      |> Enum.sort_by(& &1.label)

    sources = main_sources ++ wt_sources

    active_source =
      if assigns.port do
        Enum.find(sources, List.first(sources), fn s -> s.port == assigns.port end)
      end

    # Get output/error for the active server
    active_server =
      if active_source do
        assigns.dev_servers[active_source.id]
      end

    output = (active_server && active_server[:output]) || []
    error = active_server && active_server[:error]
    server_status = active_server && active_server.status

    assigns =
      assigns
      |> assign(:sources, sources)
      |> assign(:active_source, active_source)
      |> assign(:output, output)
      |> assign(:error, error)
      |> assign(:server_status, server_status)

    ~H"""
    <div class="flex flex-col h-full">
      <%!-- Preview bar --%>
      <div
        class="flex items-center justify-between px-4 py-2 flex-shrink-0"
        style="border-bottom: 1px solid var(--border); font-size: var(--font-size-sm);"
      >
        <div class="flex items-center gap-3">
          <button
            phx-click="close-preview"
            class="cursor-pointer"
            style="color: var(--accent); text-decoration: none;"
          >
            &larr; back
          </button>
          <span style="color: var(--border);">|</span>
          <span style="color: var(--dim);">preview</span>
          <%= if @port do %>
            <%= case @server_status do %>
              <% :error -> %>
                <span style="color: var(--error);">&#x25CF;</span>
              <% :starting -> %>
                <span style="color: var(--concocting);">
                  <.braille_spinner id="preview-bar-spin" offset={0} />
                </span>
              <% _ -> %>
                <span style="color: var(--accent);">&#x25CF;</span>
            <% end %>
          <% end %>
          <%!-- Source switcher --%>
          <%= for source <- @sources do %>
            <%= if source.port == @port do %>
              <span style="color: var(--text); font-weight: 600;">
                {source.label}
                <span style="color: var(--muted); font-weight: 400;">:{source.port}</span>
              </span>
            <% else %>
              <button
                phx-click="show-preview"
                phx-value-port={source.port}
                class="cursor-pointer"
                style="color: var(--muted);"
              >
                {source.label}
              </button>
            <% end %>
          <% end %>
        </div>
        <div class="flex items-center gap-3">
          <%= if @port do %>
            <%= if @server_status == :error and @active_source do %>
              <button
                phx-click="restart-preview"
                phx-value-id={@active_source.id}
                class="cursor-pointer"
                style="color: var(--accent);"
              >
                restart
              </button>
            <% end %>
            <button
              phx-click="toggle-preview-logs"
              class="cursor-pointer"
              style={"color: #{if @show_logs, do: "var(--text)", else: "var(--muted)"};"}
            >
              logs
              <%= if @error do %>
                <span style="color: var(--error);">!</span>
              <% end %>
            </button>
            <a
              href={"http://localhost:#{@port}"}
              target="_blank"
              style="color: var(--accent); text-decoration: none;"
            >
              open &#x2197;
            </a>
          <% end %>
          <button
            phx-click="close-preview"
            class="cursor-pointer"
            style="color: var(--muted);"
          >
            &#x2715;
          </button>
        </div>
      </div>
      <%!-- Content: port picker, logs, starting spinner, error, or iframe --%>
      <%= cond do %>
        <% is_nil(@port) -> %>
          <%!-- Port picker: show all available ports with names --%>
          <div class="flex-1 min-h-0 overflow-y-auto scroll-main px-4 py-4">
            <div style="font-size: var(--font-size-sm); color: var(--dim); margin-bottom: 12px;">
              select a preview to open
            </div>
            <div class="flex flex-col gap-2">
              <%= for source <- @sources do %>
                <button
                  phx-click="show-preview"
                  phx-value-port={source.port}
                  class="cursor-pointer text-left px-3 py-2"
                  style="border: 1px solid var(--border); border-radius: 4px; background: transparent; font-size: var(--font-size-sm);"
                  onmouseover="this.style.borderColor='var(--accent)'"
                  onmouseout="this.style.borderColor='var(--border)'"
                >
                  <span style="color: var(--text);">{source.label}</span>
                  <span style="color: var(--muted);">:{source.port}</span>
                </button>
              <% end %>
            </div>
          </div>
        <% @show_logs or @server_status == :error -> %>
          <div class="flex-1 min-h-0 overflow-y-auto scroll-main">
            <%= if @error do %>
              <div class="px-4 py-2" style="color: var(--error); font-size: var(--font-size-sm);">
                {@error}
              </div>
            <% end %>
            <div
              id="preview-logs"
              class="px-4 py-2"
              style="font-size: var(--font-size-xs); color: var(--dim); white-space: pre-wrap; font-family: var(--font-mono);"
              phx-hook="ScrollBottom"
            >
              <%= if @output == [] do %>
                <span style="color: var(--muted);">no output yet</span>
              <% else %>
                {Enum.join(@output, "\n")}
              <% end %>
            </div>
          </div>
        <% @server_status == :starting -> %>
          <div class="flex-1 min-h-0 flex flex-col">
            <div class="flex items-center gap-2 px-4 py-3" style="border-bottom: 1px solid var(--border);">
              <div style="color: var(--concocting); font-size: 18px;">
                <.braille_spinner id="preview-panel-spinner" offset={0} />
              </div>
              <div style="color: var(--dim); font-size: var(--font-size-sm);">
                starting preview server...
              </div>
            </div>
            <div
              id="preview-starting-logs"
              class="flex-1 min-h-0 overflow-y-auto scroll-main px-4 py-2"
              style="font-size: var(--font-size-xs); color: var(--dim); white-space: pre-wrap; font-family: var(--font-mono);"
              phx-hook="ScrollBottom"
            >
              <%= if @output == [] do %>
                <span style="color: var(--muted);">waiting for output...</span>
              <% else %>
                {Enum.join(@output, "\n")}
              <% end %>
            </div>
          </div>
        <% @server_status == :running -> %>
          <div class="flex-1 min-h-0">
            <iframe
              id={"preview-iframe-#{@port}"}
              src={"http://localhost:#{@port}"}
              class="w-full h-full border-0"
              style="background: white;"
              phx-update="ignore"
            />
          </div>
        <% true -> %>
          <div class="flex-1 min-h-0 flex items-center justify-center">
            <span style="color: var(--muted); font-size: var(--font-size-sm);">
              server not running
            </span>
          </div>
      <% end %>
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
  attr :questions, :list, default: []
  attr :agents, :list, default: []
  attr :input_focused, :boolean, default: false
  attr :focused_pane, :atom, default: :tree

  def moonlight_status_bar(assigns) do
    running_count = length(assigns.worktrees_by_status["running"] || [])
    pr_count = length(assigns.worktrees_by_status["pr"] || [])

    queued_count =
      length(
        (assigns.worktrees_by_status["ready"] || []) ++
          (assigns.worktrees_by_status["blocked"] || [])
      )

    done_count = length(assigns.worktrees_by_status["done"] || [])

    assigns =
      assigns
      |> assign(:running_count, running_count)
      |> assign(:pr_count, pr_count)
      |> assign(:queued_count, queued_count)
      |> assign(:done_count, done_count)

    mode =
      cond do
        assigns.input_focused -> :insert
        assigns.focused_pane == :detail -> :detail
        true -> :normal
      end

    assigns = assign(assigns, :mode, mode)

    ~H"""
    <div class="status-bar flex items-center justify-between">
      <%= cond do %>
        <% is_nil(@current_project) -> %>
          <%!-- Landing status bar --%>
          <div class="flex items-center gap-2">
            <.mode_badge mode={:normal} />
            <span style="color: var(--border);">&middot;</span>
            <span>enter open</span>
            <span style="color: var(--border);">&middot;</span>
            <span>j/k select</span>
            <span style="color: var(--border);">&middot;</span>
            <span>? help</span>
          </div>
          <div style="color: var(--muted);">v0.1.0</div>
        <% @active_tab == :workbench && @selected_task_id && @selected_task -> %>
          <%!-- Workbench with selected task --%>
          <div class="flex items-center gap-2">
            <.mode_badge mode={@mode} />
            <span style="color: var(--border);">&middot;</span>
            <%= if @input_focused do %>
              <span>esc normal</span>
              <span style="color: var(--border);">&middot;</span>
              <span>^hjkl nav</span>
            <% else %>
              <span>j/k nav</span>
              <span style="color: var(--border);">&middot;</span>
              <span>h/l panes</span>
              <span style="color: var(--border);">&middot;</span>
              <span>d diff</span>
              <span style="color: var(--border);">&middot;</span>
              <span>p preview</span>
              <span style="color: var(--border);">&middot;</span>
              <span>? help</span>
            <% end %>
          </div>
          <div class="flex items-center gap-2">
            <.braille_spinner
              :if={@running_count > 0}
              id="statusbar-bubbles-detail"
              offset={0}
              type={:bubbles}
            />
            <span style="color: var(--concocting);">&#x25CF;{@running_count}</span>
            <span style="color: var(--assaying);">&#x25CE;{@pr_count}</span>
            <span style="color: var(--muted);">&#x25CB;{@queued_count}</span>
            <span style="color: var(--bottled);">&#x25CF;{@done_count}</span>
          </div>
        <% true -> %>
          <%!-- Workbench / default status bar --%>
          <div class="flex items-center gap-2">
            <.mode_badge mode={@mode} />
            <span style="color: var(--border);">&middot;</span>
            <%= if @input_focused do %>
              <span>esc normal</span>
              <span style="color: var(--border);">&middot;</span>
              <span>^hjkl nav</span>
            <% else %>
              <span>j/k nav</span>
              <span style="color: var(--border);">&middot;</span>
              <span>h/l panes</span>
              <span style="color: var(--border);">&middot;</span>
              <span>n new</span>
              <span style="color: var(--border);">&middot;</span>
              <span>s brew</span>
              <span style="color: var(--border);">&middot;</span>
              <span>? help</span>
            <% end %>
          </div>
          <div class="flex items-center gap-2">
            <.braille_spinner
              :if={@running_count > 0}
              id="statusbar-bubbles"
              offset={0}
              type={:bubbles}
            />
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
    <div
      class="fixed inset-0 z-50 flex items-center justify-center"
      style="background: rgba(0,0,0,0.6);"
    >
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
          <p :if={@error} style="color: var(--error); font-size: var(--font-size-xs);" class="mb-2">
            {@error}
          </p>
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
              <span
                class="ml-auto truncate max-w-[180px]"
                style="color: var(--muted); font-size: var(--font-size-xs);"
              >
                {s.path}
              </span>
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
    <div
      class="fixed inset-0 z-50 flex items-center justify-center"
      style="background: rgba(0,0,0,0.6);"
    >
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
            <div class="mb-1" style="color: var(--dim); font-size: var(--font-size-xs);">
              parent directory
            </div>
            <input
              type="text"
              name="parent_dir"
              value={System.get_env("HOME", "~")}
              class="moonlight-input w-full"
            />
          </div>
          <div class="mb-3">
            <div class="mb-1" style="color: var(--dim); font-size: var(--font-size-xs);">
              project name
            </div>
            <input
              type="text"
              name="name"
              placeholder="my_app"
              autofocus
              class="moonlight-input w-full"
            />
          </div>
          <div class="mb-3">
            <div class="mb-1" style="color: var(--dim); font-size: var(--font-size-xs);">
              template
            </div>
            <div :for={tmpl <- @templates} class="flex items-center gap-2 py-1">
              <input
                type="radio"
                name="template"
                value={tmpl.id}
                checked={tmpl.id == :phoenix_no_ecto}
                style="accent-color: var(--accent);"
              />
              <span style="color: var(--text); font-size: var(--font-size-sm);">{tmpl.name}</span>
              <span style="color: var(--muted); font-size: var(--font-size-xs);">
                {tmpl.description}
              </span>
            </div>
          </div>
          <p :if={@error} style="color: var(--error); font-size: var(--font-size-xs);" class="mb-2">
            {@error}
          </p>
          <div
            :if={@progress}
            class="flex items-center gap-2 mb-2 p-2"
            style="background: var(--bg); font-size: var(--font-size-xs); color: var(--dim);"
          >
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

  # ── Adopt Worktree Modal ────────────────────────────────

  attr :error, :string, default: nil
  attr :disk_worktrees, :list, default: []

  def adopt_worktree_modal(assigns) do
    ~H"""
    <div
      class="fixed inset-0 z-50 flex items-center justify-center"
      style="background: rgba(0,0,0,0.6);"
    >
      <div
        class="w-full max-w-md mx-4 p-4"
        style="background: var(--surface); border: 1px solid var(--border);"
        phx-click-away="cancel-adopt-worktree"
        phx-window-keydown="cancel-adopt-worktree"
        phx-key="Escape"
      >
        <div class="section-header mb-3">OPEN EXISTING WORKTREE</div>

        <%= if @disk_worktrees != [] do %>
          <div class="mb-3">
            <div class="mb-1" style="color: var(--dim); font-size: var(--font-size-xs);">
              worktrees on disk
            </div>
            <div
              class="flex flex-col gap-px overflow-y-auto"
              style="max-height: 240px; border: 1px solid var(--border);"
            >
              <button
                :for={wt <- @disk_worktrees}
                type="button"
                phx-click="adopt-worktree"
                phx-value-path={wt.path}
                class={[
                  "cursor-pointer w-full text-left px-2 py-1.5 transition-colors",
                  "hover:brightness-125"
                ]}
                style="background: var(--surface-raised); font-size: var(--font-size-xs);"
              >
                <span style="color: var(--foreground);">{wt.id}</span>
                <span :if={wt.tracked} style="color: var(--muted);"> (tracked)</span>
              </button>
            </div>
          </div>
        <% end %>

        <form phx-submit="adopt-worktree" id="adopt-worktree-form">
          <div class="mb-3">
            <div class="mb-1" style="color: var(--dim); font-size: var(--font-size-xs);">
              or enter path manually
            </div>
            <input
              type="text"
              name="path"
              placeholder="~/.apothecary/worktrees/..."
              autofocus={@disk_worktrees == []}
              class="moonlight-input w-full"
            />
          </div>
          <p :if={@error} style="color: var(--error); font-size: var(--font-size-xs);" class="mb-2">
            {@error}
          </p>
          <div class="flex justify-end gap-2">
            <button type="button" phx-click="cancel-adopt-worktree" class="action-text">
              cancel
            </button>
            <button type="submit" class="action-pill">open</button>
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
      <div
        class="flex items-center justify-between px-4 py-2 shrink-0"
        style="border-bottom: 1px solid var(--border);"
      >
        <div class="flex items-center gap-3">
          <span class="section-header" style="color: var(--accent);">DIFF</span>
          <span style="color: var(--dim); font-size: var(--font-size-sm);">{@diff.worktree_id}</span>
          <span
            :if={@diff.loading}
            style="color: var(--concocting); font-size: var(--font-size-xs);"
            class="animate-pulse"
          >
            loading...
          </span>
        </div>
        <span style="color: var(--muted); font-size: var(--font-size-xs);">
          esc close  j/k navigate
        </span>
      </div>

      <div :if={@diff.error && !@diff.loading} class="flex-1 flex items-center justify-center">
        <div class="text-center">
          <div id="diff-error-text" style="color: var(--error); font-size: var(--font-size-sm);">
            {@diff.error}
          </div>
          <.copy_button target="#diff-error-text" class="mt-2" />
        </div>
      </div>

      <div :if={@diff.loading} class="flex-1 flex items-center justify-center">
        <span style="color: var(--concocting);" class="animate-pulse">fetching diff...</span>
      </div>

      <div
        :if={!@diff.loading && !@diff.error && @diff.files != []}
        class="flex flex-1 overflow-hidden"
      >
        <div
          id="diff-file-list"
          class="w-64 shrink-0 overflow-y-auto"
          style="border-right: 1px solid var(--border); background: var(--surface);"
        >
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
            <div
              class="sticky top-0 px-4 py-1"
              style="background: var(--surface); border-bottom: 1px solid var(--border); color: var(--dim);"
            >
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

      <div
        :if={!@diff.loading && !@diff.error && @diff.files == []}
        class="flex-1 flex items-center justify-center"
      >
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
            <.hk key="j/k" desc="next/prev worktree" />
            <.hk key="h/l" desc="focus worktrees/detail" />
            <.hk key="^h/l" desc="focus worktrees/detail (from input)" />
            <.hk key="^j/k" desc="cycle sections: tree → detail → input" />
            <.hk key="g/G" desc="first/last worktree" />
            <.hk key="1-4" desc="jump to lane" />
            <.hk key="enter" desc="focus worktree" />
            <.hk key="w" desc="back to worktrees" />
            <.hk key="esc" desc="normal mode / back" />
            <.hk key="⌘k" desc="switch project" />
          </div>

          <div>
            <div style="color: var(--accent);" class="mb-1">input (insert mode)</div>
            <.hk key="b" desc="new worktree" />
            <.hk key="c / /" desc="chat mode (message brewer)" />
            <.hk key="n" desc="focus input" />
            <.hk key="a" desc="task mode (add to worktree)" />
            <.hk key="+ (in chat)" desc="switch to task mode" />
            <.hk key="?text" desc="ask question" />
          </div>

          <div>
            <div style="color: var(--accent);" class="mb-1">actions</div>
            <.hk key="s" desc="start/stop brewing" />
            <.hk key="+/-" desc="brewer count" />
            <.hk key="J/K" desc="reorder priority" />
            <.hk key="d" desc="view diff" />
            <.hk key="t" desc="open terminal" />
            <.hk key="p" desc="open preview" />
            <.hk key="P" desc="pull origin main" />
            <.hk key="?" desc="this help" />
          </div>

          <div>
            <div style="color: var(--accent);" class="mb-1">global</div>
            <.hk key="R" desc="requeue orphans" />
            <.hk key="D" desc="delete worktree" />
            <.hk key="e" desc="recurring tasks" />
            <.hk key="?text" desc="ask question" />
          </div>

          <div :if={@has_selected_task}>
            <div style="color: var(--accent);" class="mb-1">detail view</div>
            <.hk key="m" desc="merge" />
            <.hk key="r" desc="requeue" />
            <.hk key="x" desc="close worktree" />
          </div>
        </div>
      </div>
    </div>
    """
  end

  defp mode_badge(assigns) do
    {label, color} =
      case assigns.mode do
        :insert -> {"INSERT", "var(--concocting)"}
        :detail -> {"DETAIL", "var(--assaying)"}
        _ -> {"NORMAL", "var(--accent)"}
      end

    assigns = assigns |> assign(:label, label) |> assign(:color, color)

    ~H"""
    <span style={"color: #{@color}; font-weight: 600;"}>{@label}</span>
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
        <span :if={@next_run} style="color: var(--dim);">
          next run {format_relative_time(@next_run)}
        </span>
      </div>

      <.recipe_form :if={@show_recipe_form} form={@recipe_form} editing_id={@editing_recipe_id} />

      <%= if @recipes == [] and !@show_recipe_form do %>
        <div style="color: var(--muted); font-size: var(--font-size-sm);" class="py-6">
          no recurring worktrees yet
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
        <button
          phx-click="show-recipe-form"
          style="color: var(--muted); font-size: var(--font-size-sm); cursor: pointer;"
        >
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
          <div class="mb-1" style="color: var(--dim); font-size: var(--font-size-xs);">
            description
          </div>
          <textarea
            name="recipe[description]"
            rows="3"
            placeholder="Task description for the worktree..."
            class="moonlight-input w-full resize-none"
          >{@form[:description].value}</textarea>
        </div>
        <div class="grid grid-cols-2 gap-3 mb-2">
          <div>
            <div class="mb-1" style="color: var(--dim); font-size: var(--font-size-xs);">
              schedule (cron)
            </div>
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
            <div class="mb-1" style="color: var(--dim); font-size: var(--font-size-xs);">
              priority
            </div>
            <select name="recipe[priority]" class="moonlight-input w-full">
              <option value="0" selected={@form[:priority].value == "0"}>P0 - Critical</option>
              <option value="1" selected={@form[:priority].value == "1"}>P1 - High</option>
              <option value="2" selected={@form[:priority].value == "2"}>P2 - Medium</option>
              <option value="3" selected={@form[:priority].value in [nil, "", "3"]}>
                P3 - Default
              </option>
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
            <div
              class="flex items-center gap-1 pl-7 pb-1"
              style="color: var(--muted); font-size: var(--font-size-xs);"
            >
              <span style="color: var(--dim);">{recipe.schedule}</span>
              <span :if={recipe.last_run_at}>
                &middot; last: {format_relative_time(recipe.last_run_at)}
              </span>
              <span :if={recipe.next_run_at}>
                &middot; next: {format_relative_time(recipe.next_run_at)}
              </span>
              <span class="ml-auto flex items-center gap-1">
                <button
                  phx-click="toggle-recipe"
                  phx-value-id={recipe.id}
                  class="action-text"
                  style="font-size: var(--font-size-xs);"
                >
                  {if(recipe.enabled, do: "pause", else: "resume")}
                </button>
                <button
                  phx-click="delete-recipe"
                  phx-value-id={recipe.id}
                  class="action-text"
                  style="font-size: var(--font-size-xs);"
                  data-confirm="Delete this recipe?"
                >
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
        :for={{tab, label} <- [workbench: "workbench", recipes: "recurring"]}
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
      <div class="flex items-center gap-2">
        <span>{page_label(@page)}</span>
        <%= if @page == :agent do %>
          <span style="color: var(--border);">&middot;</span>
          <span>bksp back</span>
          <span style="color: var(--border);">&middot;</span>
          <span>? help</span>
        <% end %>
      </div>
      <span>? help</span>
    </div>
    """
  end

  defp page_label(:dashboard), do: "NORMAL"
  defp page_label(:agent), do: "NORMAL"
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

  # ── Question Thread Item ─────────────────────────────────

  attr :q, :map, required: true
  attr :depth, :integer, default: 0
  attr :follow_up_id, :string, default: nil

  defp question_thread_item(assigns) do
    answer = question_answer(assigns.q)
    is_follow_up_open = assigns.follow_up_id == assigns.q.id
    indent_ml = if assigns.depth > 0, do: "ml-5", else: ""
    marker = if assigns.depth > 0, do: "○", else: "?"

    assigns =
      assigns
      |> assign(:answer, answer)
      |> assign(:is_follow_up_open, is_follow_up_open)
      |> assign(:indent_ml, indent_ml)
      |> assign(:marker, marker)

    ~H"""
    <div class={[@indent_ml, "mb-3"]}>
      <%!-- Question --%>
      <div class="flex items-start gap-2" style="font-size: var(--font-size-sm);">
        <span style="color: var(--accent); font-weight: 600; flex-shrink: 0;">{@marker}</span>
        <span style="color: var(--text); font-weight: 500;">{@q.title}</span>
      </div>
      <%!-- Answer --%>
      <%= if @answer != "" do %>
        <div
          id={"q-answer-#{@q.id}"}
          class="ml-5 mt-2 px-3 py-2 question-answer"
          style={[
            "border-left: 2px solid color-mix(in srgb, var(--accent) 40%, transparent);",
            "background: color-mix(in srgb, var(--surface) 80%, transparent);",
            "border-radius: 0 6px 6px 0;",
            "font-size: var(--font-size-sm); color: var(--dim);",
            "white-space: pre-wrap; line-height: 1.6;"
          ]}
        >
          {@answer}
        </div>
        <div class="ml-5 mt-1 flex items-center gap-2">
          <.copy_button target={"#q-answer-#{@q.id}"} class="ml-3" />
          <button
            phx-click="toggle-follow-up"
            phx-value-question-id={@q.id}
            style="color: var(--muted); font-size: var(--font-size-xs);"
            class="hover:underline cursor-pointer"
          >
            follow up
          </button>
        </div>
        <%!-- Follow-up input --%>
        <%= if @is_follow_up_open do %>
          <form
            phx-submit="submit-follow-up"
            id={"follow-up-form-#{@q.id}"}
            class="ml-5 mt-2 flex items-center gap-2 px-3 py-2"
            style="font-size: var(--font-size-sm); background: color-mix(in srgb, var(--accent) 8%, var(--bg)); border: 1px solid color-mix(in srgb, var(--accent) 25%, transparent); border-radius: 6px;"
          >
            <input type="hidden" name="parent_question_id" value={@q.id} />
            <span style="color: var(--accent); font-weight: 600;">?</span>
            <input
              type="text"
              name="follow_up_text"
              placeholder="follow-up question..."
              autofocus
              class="flex-1 bg-transparent outline-none"
              style="color: var(--text); border: none; padding: 2px 0; font-size: var(--font-size-sm);"
            />
            <span style="color: var(--muted); font-size: var(--font-size-xs);">
              enter &middot; esc close
            </span>
          </form>
        <% end %>
      <% else %>
        <%!-- In-progress: show thinking indicator --%>
        <div
          :if={@q.status in ["open", "in_progress"]}
          class="ml-5 mt-2 pl-3 flex items-center gap-2"
          style="border-left: 2px solid color-mix(in srgb, var(--accent) 40%, transparent); font-size: var(--font-size-sm); color: var(--muted);"
        >
          <.braille_spinner id={"q-spin-#{@q.id}"} offset={0} />
          <span>thinking...</span>
        </div>
      <% end %>
    </div>
    """
  end

  # ── Helper functions ─────────────────────────────────────

  defp question_answer(q) do
    notes = q.notes || ""

    notes
    |> String.replace(~r/^\[\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}\]\s*/, "")
    |> String.trim()
  end

  # Group questions into threaded conversations.
  # Root questions (no parent_question_id) start threads;
  # follow-ups are nested under their parent.
  defp group_questions_threaded(questions) do
    by_parent = Enum.group_by(questions, & &1.parent_question_id)
    roots = Map.get(by_parent, nil, [])

    Enum.map(roots, fn root ->
      build_thread(root, by_parent, 0)
    end)
  end

  defp build_thread(q, by_parent, depth) do
    q_with_depth = Map.put(q, :__depth__, depth)
    children = Map.get(by_parent, q.id, [])

    [q_with_depth | Enum.flat_map(children, &build_thread(&1, by_parent, depth + 1))]
  end

  defp task_status_group(task) do
    case task.status do
      s when s in ["in_progress", "claimed"] -> "brewing"
      s when s in ["brew_done", "pr_open", "revision_needed"] -> "reviewing"
      "merged" -> "bottled"
      s when s in ["done", "closed", "cancelled"] -> "discarded"
      _ -> "queued"
    end
  end

  defp group_color("brewing"), do: "var(--concocting)"
  defp group_color("reviewing"), do: "var(--assaying)"
  defp group_color("bottled"), do: "var(--bottled)"
  defp group_color("discarded"), do: "var(--dim)"
  defp group_color("queued"), do: "var(--muted)"
  defp group_color(_), do: "var(--dim)"

  defp group_dot("brewing"), do: "◉"
  defp group_dot("reviewing"), do: "◎"
  defp group_dot("bottled"), do: "●"
  defp group_dot("discarded"), do: "✕"
  defp group_dot("queued"), do: "○"
  defp group_dot(_), do: "·"

  defp loading_label(:merging), do: "merging PR..."
  defp loading_label(:direct_merging), do: "creating PR & merging..."
  defp loading_label(:creating_pr), do: "creating PR..."
  defp loading_label(:local_merging), do: "merging locally..."
  defp loading_label(_), do: "working..."

  defp worktree_count_label(project_id) do
    count = length(Apothecary.Worktrees.list_worktrees(project_id: project_id))

    case count do
      0 -> "0 worktrees"
      1 -> "1 worktree"
      n -> "#{n} worktrees"
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
