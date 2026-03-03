defmodule ApothecaryWeb.DashboardComponents do
  @moduledoc "Card-based function components for the swarm dashboard."
  use Phoenix.Component
  import ApothecaryWeb.CoreComponents, only: [icon: 1]

  use Phoenix.VerifiedRoutes,
    endpoint: ApothecaryWeb.Endpoint,
    router: ApothecaryWeb.Router,
    statics: ApothecaryWeb.static_paths()

  # --- Copy to clipboard button ---

  attr :target, :string, required: true, doc: "CSS selector of the element whose text to copy"
  attr :class, :string, default: ""

  def copy_button(assigns) do
    ~H"""
    <button
      id={"copy-btn-" <> String.replace(@target, ~r/[^a-zA-Z0-9]/, "")}
      phx-hook=".CopyText"
      data-copy-target={@target}
      class={[
        "text-base-content/30 hover:text-base-content/60 cursor-pointer transition-colors text-xs",
        @class
      ]}
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
              this.el.classList.add("text-green-400")
              setTimeout(() => {
                this.el.textContent = original
                this.el.classList.remove("text-green-400")
              }, 1500)
            })
          })
        }
      }
    </script>
    """
  end

  # --- Project Selector ---

  attr :projects, :list, required: true
  attr :current_project, :any, default: nil

  def project_selector(assigns) do
    display_name =
      cond do
        assigns.current_project -> assigns.current_project.name
        assigns.projects != [] -> "Select Project"
        true -> "Apothecary"
      end

    assigns = assign(assigns, :display_name, display_name)

    ~H"""
    <div class="relative min-w-0" id="project-dropdown" phx-hook=".ProjectDropdown">
      <button
        class="flex items-center gap-1.5 px-2 py-1 rounded hover:bg-base-content/5 transition-colors cursor-pointer min-w-0"
        phx-click={toggle_dropdown()}
        type="button"
      >
        <span class="font-apothecary font-bold text-sm sm:text-base text-base-content truncate max-w-[200px] sm:max-w-[300px]">
          {@display_name}
        </span>
        <.icon name="hero-chevron-down" class="w-4 h-4 text-base-content/40 shrink-0" />
      </button>
      <div
        id="project-dropdown-menu"
        class="hidden absolute left-0 top-full mt-1 bg-base-100 border border-base-content/10 rounded-lg shadow-xl z-50 min-w-[220px] max-w-[320px] py-1"
      >
        <.link
          :for={project <- @projects}
          navigate={~p"/projects/#{project.id}"}
          class={[
            "flex items-center gap-2 px-3 py-2 text-sm hover:bg-base-content/5 transition-colors cursor-pointer",
            if(@current_project && @current_project.id == project.id,
              do: "text-base-content font-semibold bg-base-content/5",
              else: "text-base-content/70"
            )
          ]}
          title={project.path}
        >
          <span class="truncate">{project.name}</span>
          <span
            :if={@current_project && @current_project.id == project.id}
            class="ml-auto text-primary text-xs shrink-0"
          >
            &#x2713;
          </span>
        </.link>
        <div :if={@projects != []} class="border-t border-base-content/10 my-1" />
        <button
          phx-click="show-add-project"
          class="flex items-center gap-2 w-full px-3 py-2 text-sm text-base-content/50 hover:text-base-content/70 hover:bg-base-content/5 transition-colors cursor-pointer"
        >
          <.icon name="hero-folder-open" class="w-4 h-4" />
          <span>Open Project</span>
        </button>
        <button
          phx-click="show-new-project"
          class="flex items-center gap-2 w-full px-3 py-2 text-sm text-base-content/50 hover:text-base-content/70 hover:bg-base-content/5 transition-colors cursor-pointer"
        >
          <.icon name="hero-plus" class="w-4 h-4" />
          <span>New Project</span>
        </button>
      </div>
    </div>
    <script :type={Phoenix.LiveView.ColocatedHook} name=".ProjectDropdown">
      export default {
        mounted() {
          this.menu = this.el.querySelector("#project-dropdown-menu")
          this.closeHandler = (e) => {
            if (!this.el.contains(e.target)) {
              this.menu.classList.add("hidden")
            }
          }
          document.addEventListener("click", this.closeHandler)
          // Close on navigation
          this.handleEvent("close-dropdown", () => {
            this.menu.classList.add("hidden")
          })
        },
        destroyed() {
          document.removeEventListener("click", this.closeHandler)
        }
      }
    </script>
    """
  end

  defp toggle_dropdown do
    Phoenix.LiveView.JS.toggle(
      to: "#project-dropdown-menu",
      in: {"ease-out duration-100", "opacity-0 scale-95", "opacity-100 scale-100"},
      out: {"ease-in duration-75", "opacity-100 scale-100", "opacity-0 scale-95"}
    )
  end

  # --- Add Project Modal ---

  attr :error, :string, default: nil
  attr :suggestions, :list, default: []

  def add_project_modal(assigns) do
    ~H"""
    <div class="fixed inset-0 bg-black/50 z-50 flex items-center justify-center">
      <div
        class="bg-base-100 rounded-lg shadow-xl p-6 w-full max-w-md mx-4"
        phx-click-away="cancel-add-project"
        phx-window-keydown="cancel-add-project"
        phx-key="Escape"
      >
        <h3 class="text-lg font-apothecary font-semibold mb-4">Open Project</h3>
        <form phx-submit="add-project" phx-change="search-project-path" class="space-y-4">
          <div>
            <label class="block text-sm text-base-content/60 mb-1">Project path</label>
            <input
              type="text"
              name="path"
              placeholder="/home/user/my-project"
              autofocus
              autocomplete="off"
              phx-debounce="150"
              class="w-full px-3 py-2 bg-base-200 border border-base-content/10 rounded text-sm focus:outline-none focus:border-primary/50"
            />
            <p :if={@error} class="text-error text-xs mt-1">{@error}</p>
            <p :if={@suggestions == []} class="text-base-content/30 text-xs mt-1">
              Enter the absolute path to a git repository.
            </p>
          </div>
          <div
            :if={@suggestions != []}
            class="bg-base-200 border border-base-content/10 rounded max-h-40 overflow-y-auto -mt-2"
          >
            <button
              :for={s <- @suggestions}
              type="button"
              phx-click="select-project-path"
              phx-value-path={s.path}
              class="w-full text-left px-3 py-1.5 text-sm hover:bg-base-content/10 flex items-center gap-2 cursor-pointer"
            >
              <span :if={s.is_git} class="text-emerald-400 text-xs shrink-0" title="git repo">
                &#x25CF;
              </span>
              <span :if={!s.is_git} class="text-base-content/20 text-xs shrink-0">&#x25CB;</span>
              <span class="truncate">{s.name}</span>
              <span class="ml-auto text-base-content/20 text-xs shrink-0 truncate max-w-[180px]">
                {s.path}
              </span>
            </button>
          </div>
          <div class="flex justify-end gap-2">
            <button
              type="button"
              phx-click="cancel-add-project"
              class="px-3 py-1.5 text-sm text-base-content/50 hover:text-base-content cursor-pointer"
            >
              Cancel
            </button>
            <button
              type="submit"
              class="px-4 py-1.5 text-sm bg-primary/20 text-primary hover:bg-primary/30 rounded transition-colors cursor-pointer"
            >
              Open
            </button>
          </div>
        </form>
      </div>
    </div>
    """
  end

  # --- Concoct Controls (above textarea area) ---

  attr :swarm_status, :atom, default: :paused
  attr :target_count, :integer, default: 3
  attr :active_count, :integer, default: 0
  attr :working_count, :integer, default: 0
  attr :auto_pr, :boolean, default: false
  attr :gh_available, :boolean, default: false

  # --- New Project (Bootstrap) Modal ---

  attr :error, :string, default: nil
  attr :progress, :string, default: nil

  def new_project_modal(assigns) do
    templates = Apothecary.Bootstrapper.templates()
    assigns = assign(assigns, :templates, templates)

    ~H"""
    <div class="fixed inset-0 bg-black/50 z-50 flex items-center justify-center">
      <div
        class="bg-base-100 rounded-lg shadow-xl p-6 w-full max-w-md mx-4"
        phx-click-away="cancel-new-project"
        phx-window-keydown="cancel-new-project"
        phx-key="Escape"
      >
        <h3 class="text-lg font-apothecary font-semibold mb-4">New Project</h3>
        <form phx-submit="create-new-project" id="new-project-form" class="space-y-4">
          <div>
            <label class="block text-sm text-base-content/60 mb-1">Parent directory</label>
            <input
              type="text"
              name="parent_dir"
              placeholder="/home/user/projects"
              value={System.get_env("HOME", "~")}
              class="w-full px-3 py-2 bg-base-200 border border-base-content/10 rounded text-sm focus:outline-none focus:border-primary/50"
            />
          </div>
          <div>
            <label class="block text-sm text-base-content/60 mb-1">Project name</label>
            <input
              type="text"
              name="name"
              placeholder="my_app"
              autofocus
              class="w-full px-3 py-2 bg-base-200 border border-base-content/10 rounded text-sm focus:outline-none focus:border-primary/50"
            />
            <p class="text-base-content/30 text-xs mt-1">
              Lowercase letters, numbers, and underscores only (e.g. my_app)
            </p>
          </div>
          <div>
            <label class="block text-sm text-base-content/60 mb-1">Template</label>
            <div class="space-y-2">
              <label
                :for={tmpl <- @templates}
                class="flex items-center gap-3 p-2 bg-base-200/50 rounded cursor-pointer hover:bg-base-200"
              >
                <input
                  type="radio"
                  name="template"
                  value={tmpl.id}
                  checked={tmpl.id == :phoenix_no_ecto}
                  class="radio radio-sm"
                />
                <div>
                  <div class="text-sm font-medium">{tmpl.name}</div>
                  <div class="text-xs text-base-content/40">{tmpl.description}</div>
                </div>
              </label>
            </div>
          </div>
          <p :if={@error} class="text-error text-xs">{@error}</p>
          <div
            :if={@progress}
            class="text-sm text-base-content/50 bg-base-200 rounded p-2 font-mono text-xs"
          >
            {@progress}
          </div>
          <div class="flex justify-end gap-2">
            <button
              type="button"
              phx-click="cancel-new-project"
              class="px-3 py-1.5 text-sm text-base-content/50 hover:text-base-content cursor-pointer"
            >
              Cancel
            </button>
            <button
              type="submit"
              disabled={@progress != nil}
              class={[
                "px-4 py-1.5 text-sm rounded transition-colors cursor-pointer",
                if(@progress,
                  do: "bg-base-content/10 text-base-content/30",
                  else: "bg-primary/20 text-primary hover:bg-primary/30"
                )
              ]}
            >
              {if @progress, do: "Creating...", else: "Create"}
            </button>
          </div>
        </form>
      </div>
    </div>
    """
  end

  # --- Project Preview ---

  attr :project, :any, required: true
  attr :dev_server, :any, default: nil

  def project_preview(assigns) do
    ~H"""
    <div class="mb-4">
      <%= cond do %>
        <% @dev_server && @dev_server.status in [:starting, :running] -> %>
          <div class="rounded-lg border border-base-content/10 overflow-hidden">
            <div class="flex items-center justify-between px-3 py-2 bg-base-200/50">
              <div class="flex items-center gap-2">
                <span class={[
                  "w-2 h-2 rounded-full",
                  if(@dev_server.status == :running,
                    do: "bg-green-400",
                    else: "bg-amber-400 animate-pulse"
                  )
                ]} />
                <span class="text-xs text-base-content/60 font-apothecary">
                  {if @dev_server.status == :running, do: "Running", else: "Starting..."}
                </span>
                <%= for port_info <- @dev_server.ports || [] do %>
                  <a
                    href={"http://localhost:#{port_info.port}"}
                    target="_blank"
                    class="text-xs text-primary hover:text-primary/80 transition-colors"
                  >
                    :{port_info.port}
                  </a>
                <% end %>
              </div>
              <button
                phx-click="stop-project-dev"
                class="text-xs text-base-content/40 hover:text-error transition-colors cursor-pointer"
              >
                Stop
              </button>
            </div>
            <%= if @dev_server.status == :running do %>
              <% port = List.first(@dev_server.ports || []) %>
              <%= if port do %>
                <iframe
                  src={"http://localhost:#{port.port}"}
                  class="w-full h-[300px] sm:h-[400px] border-t border-base-content/10 bg-white"
                  title={"#{@project.name} preview"}
                />
              <% end %>
            <% end %>
          </div>
        <% @dev_server && @dev_server.status == :error -> %>
          <div class="rounded-lg border border-error/20 p-3">
            <div class="flex items-center justify-between">
              <span class="text-xs text-error/70">{@dev_server.error || "Server error"}</span>
              <button
                phx-click="start-project-dev"
                class="text-xs text-primary hover:text-primary/80 transition-colors cursor-pointer"
              >
                Retry
              </button>
            </div>
          </div>
        <% true -> %>
          <button
            phx-click="start-project-dev"
            class="w-full flex items-center justify-center gap-2 px-4 py-3 rounded-lg border border-dashed border-base-content/15 hover:border-base-content/30 text-base-content/40 hover:text-base-content/60 transition-colors cursor-pointer"
          >
            <.icon name="hero-play" class="w-4 h-4" />
            <span class="text-sm font-apothecary">Start Preview</span>
          </button>
      <% end %>
    </div>
    """
  end

  def concoct_controls(assigns) do
    ~H"""
    <div class="flex items-center gap-3 mb-3 text-xs flex-wrap">
      <%= if @swarm_status == :running do %>
        <button
          phx-click="stop-swarm"
          class="flex items-center gap-2 text-base-content/70 hover:text-base-content px-3 py-2 cursor-pointer font-apothecary text-sm transition-colors"
          title="Click to stop concocting (s)"
        >
          <.cauldron_icon animating={true} size={80} />
          <span class="text-base">Concocting</span>
          <span class="text-base-content/30 text-xs ml-1 hidden sm:inline">[s]</span>
        </button>
      <% else %>
        <button
          phx-click="start-swarm"
          class="flex items-center gap-2 text-base-content/40 hover:text-base-content/70 px-3 py-2 cursor-pointer font-apothecary text-sm transition-colors"
          title="Click to start concocting (s)"
        >
          <.cauldron_icon animating={false} size={80} />
          <span class="text-base">Concoct</span>
          <span class="text-base-content/30 text-xs ml-1 hidden sm:inline">[s]</span>
        </button>
      <% end %>

      <span class="text-base-content/20 hidden sm:inline">│</span>

      <div class="flex items-center gap-1">
        <button
          phx-click="dec-agents"
          class="text-base-content/50 hover:text-base-content cursor-pointer px-2 py-1"
        >
          -
        </button>
        <span class="text-base-content/50">{@target_count} alchemists</span>
        <button
          phx-click="inc-agents"
          class="text-base-content/50 hover:text-base-content cursor-pointer px-2 py-1"
        >
          +
        </button>
      </div>

      <span class="text-base-content/20 hidden sm:inline">│</span>

      <.auto_pr_toggle auto_pr={@auto_pr} gh_available={@gh_available} />
    </div>
    """
  end

  # --- Auto PR Toggle ---

  attr :auto_pr, :boolean, default: false
  attr :gh_available, :boolean, default: false

  def auto_pr_toggle(assigns) do
    ~H"""
    <label class="flex items-center gap-1.5 cursor-pointer select-none group">
      <input
        type="checkbox"
        checked={@auto_pr}
        phx-click="toggle-auto-pr"
        class="accent-purple-400 w-3.5 h-3.5 cursor-pointer"
      />
      <span class={[
        "text-xs transition-colors",
        if(@auto_pr,
          do: "text-base-content/70",
          else: "text-base-content/40 group-hover:text-base-content/60"
        )
      ]}>
        Auto PR
      </span>
      <%= if !@gh_available do %>
        <span class="text-amber-400/50 text-[10px] hidden sm:inline" title="gh CLI not installed">
          (no gh)
        </span>
      <% end %>
    </label>
    """
  end

  # --- Cauldron SVG Icon ---

  attr :animating, :boolean, default: false
  attr :size, :integer, default: 48

  def cauldron_icon(assigns) do
    ~H"""
    <svg
      width={@size}
      height={@size}
      viewBox="0 0 64 64"
      fill="none"
      xmlns="http://www.w3.org/2000/svg"
      class={["cauldron-svg", @animating && "cauldron-brewing"]}
    >
      <%!-- Iron bail handle --%>
      <path
        d="M14 26 C14 10, 50 10, 50 26"
        fill="none"
        stroke="#3a3a3a"
        stroke-width="2.5"
        stroke-linecap="round"
      />
      <%!-- Handle attachment rings --%>
      <circle cx="14" cy="26" r="2" fill="#2a2a2a" stroke="#444" stroke-width="0.8" />
      <circle cx="50" cy="26" r="2" fill="#2a2a2a" stroke="#444" stroke-width="0.8" />

      <%!-- Rim — thick iron band --%>
      <ellipse cx="32" cy="28" rx="21" ry="7" fill="#2a2a2a" stroke="#444" stroke-width="1.5" />
      <ellipse cx="32" cy="28" rx="19" ry="5.5" fill="none" stroke="#555" stroke-width="0.5" />

      <%!-- Cauldron body — big round belly --%>
      <path
        d="M11 28 C11 28, 8 38, 12 46 C16 54, 48 54, 52 46 C56 38, 53 28, 53 28"
        fill="#1a1a1a"
        stroke="#333"
        stroke-width="1.2"
      />
      <%!-- Body highlight — curved iron sheen --%>
      <path
        d="M15 32 C14 38, 16 44, 22 48"
        fill="none"
        stroke="#3a3a3a"
        stroke-width="1"
        opacity="0.6"
        stroke-linecap="round"
      />

      <%!-- Iron rivets/studs on body --%>
      <circle cx="16" cy="34" r="1" fill="#3a3a3a" />
      <circle cx="48" cy="34" r="1" fill="#3a3a3a" />
      <circle cx="14" cy="40" r="1" fill="#3a3a3a" />
      <circle cx="50" cy="40" r="1" fill="#3a3a3a" />

      <%!-- Decorative band around middle --%>
      <path
        d="M13 38 C13 38, 22 42, 32 42 C42 42, 51 38, 51 38"
        fill="none"
        stroke="#3a3a3a"
        stroke-width="0.8"
        opacity="0.5"
      />

      <%!-- Liquid inside --%>
      <ellipse cx="32" cy="30" rx="17" ry="4.5" fill="#1a472a" opacity="0.9" />
      <%!-- Liquid surface shimmer --%>
      <ellipse cx="28" cy="29.5" rx="7" ry="2.5" fill="#2d6b3f" opacity="0.5" />

      <%!-- Three stubby iron legs --%>
      <path d="M18 50 L15 58 L19 58 Z" fill="#2a2a2a" stroke="#3a3a3a" stroke-width="0.5" />
      <path d="M46 50 L45 58 L49 58 Z" fill="#2a2a2a" stroke="#3a3a3a" stroke-width="0.5" />
      <path d="M32 52 L30 60 L34 60 Z" fill="#2a2a2a" stroke="#3a3a3a" stroke-width="0.5" />

      <%!-- Animated elements when brewing --%>
      <%= if @animating do %>
        <%!-- Stirring ladle --%>
        <g class="cauldron-ladle">
          <%!-- Ladle handle (near-vertical stick leaning slightly right) --%>
          <line
            x1="32"
            y1="28"
            x2="38"
            y2="6"
            stroke="#8B6914"
            stroke-width="2"
            stroke-linecap="round"
          />
          <%!-- Ladle bowl --%>
          <ellipse cx="32" cy="30" rx="4" ry="2" fill="#6B5210" stroke="#8B6914" stroke-width="0.8" />
        </g>

        <%!-- Bubbles --%>
        <circle
          class="cauldron-bubble cauldron-bubble-1"
          cx="26"
          cy="28"
          r="1.5"
          fill="#4ade80"
          opacity="0.7"
        />
        <circle
          class="cauldron-bubble cauldron-bubble-2"
          cx="36"
          cy="27"
          r="2"
          fill="#34d399"
          opacity="0.6"
        />
        <circle
          class="cauldron-bubble cauldron-bubble-3"
          cx="30"
          cy="29"
          r="1"
          fill="#6ee7b7"
          opacity="0.8"
        />
        <circle
          class="cauldron-bubble cauldron-bubble-4"
          cx="38"
          cy="28"
          r="1.3"
          fill="#4ade80"
          opacity="0.5"
        />

        <%!-- Steam wisps --%>
        <path
          class="cauldron-steam cauldron-steam-1"
          d="M24 24 C22 18, 26 14, 24 8"
          stroke="#4ade80"
          stroke-width="1"
          fill="none"
          opacity="0.3"
          stroke-linecap="round"
        />
        <path
          class="cauldron-steam cauldron-steam-2"
          d="M32 22 C34 16, 30 12, 32 6"
          stroke="#34d399"
          stroke-width="1.2"
          fill="none"
          opacity="0.25"
          stroke-linecap="round"
        />
        <path
          class="cauldron-steam cauldron-steam-3"
          d="M40 24 C42 18, 38 14, 40 8"
          stroke="#6ee7b7"
          stroke-width="0.8"
          fill="none"
          opacity="0.2"
          stroke-linecap="round"
        />
      <% end %>
    </svg>
    """
  end

  # --- Primary Input (big textarea at top) ---

  attr :input_focused, :boolean, default: false

  def primary_input(assigns) do
    ~H"""
    <div class="relative">
      <textarea
        id="primary-input"
        rows="5"
        placeholder=""
        phx-hook="TextareaSubmit"
        phx-focus="input-focus"
        phx-blur="input-blur"
        autocomplete="off"
        class="bg-transparent border border-base-content/20 focus:border-primary outline-none px-3 py-2 pr-12 text-sm w-full resize-none rounded-lg"
      ></textarea>
      <div
        id="file-autocomplete-dropdown"
        phx-update="ignore"
        class="hidden absolute left-0 right-0 bottom-full mb-1 max-h-48 overflow-y-auto rounded-lg border border-base-content/20 bg-base-200 shadow-lg z-50 text-sm"
      >
      </div>
      <button
        id="primary-input-send"
        phx-hook=".TextareaSend"
        type="button"
        class="absolute right-2 bottom-2 text-base-content/30 hover:text-primary cursor-pointer p-1.5 rounded hover:bg-base-content/10 transition-colors"
        title="Send (Enter)"
      >
        <svg
          xmlns="http://www.w3.org/2000/svg"
          viewBox="0 0 20 20"
          fill="currentColor"
          class="w-5 h-5"
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
        <div class={["text-sm font-bold truncate", lane_color(@group)]}>
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
      <div class="px-3 pb-2 pt-1">
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
            class="bg-transparent border border-base-content/10 focus:border-primary outline-none px-2 py-1.5 text-sm flex-1 min-w-0 rounded"
          />
          <button
            type="submit"
            class="text-base-content/25 hover:text-primary cursor-pointer p-1 rounded hover:bg-base-content/10 transition-colors shrink-0"
            title="Add ingredient"
          >
            <svg
              xmlns="http://www.w3.org/2000/svg"
              viewBox="0 0 20 20"
              fill="currentColor"
              class="w-4 h-4"
            >
              <path d="M10.75 4.75a.75.75 0 0 0-1.5 0v4.5h-4.5a.75.75 0 0 0 0 1.5h4.5v4.5a.75.75 0 0 0 1.5 0v-4.5h4.5a.75.75 0 0 0 0-1.5h-4.5v-4.5Z" />
            </svg>
          </button>
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
  attr :has_preview_config, :boolean, default: false
  attr :pending_action, :any, default: nil

  def task_detail_drawer(assigns) do
    ~H"""
    <div class="fixed inset-0 z-40" phx-window-keydown="hotkey">
      <%!-- Backdrop --%>
      <div
        class="absolute inset-0 bg-black/50"
        phx-click="deselect-task"
      />

      <%!-- Drawer panel --%>
      <div class="absolute right-0 top-0 bottom-0 w-full sm:max-w-lg bg-base-100 border-l border-base-content/10 flex flex-col">
        <%!-- Sticky header --%>
        <div class="flex items-center justify-between px-4 py-3 border-b border-base-content/10 shrink-0">
          <div class="flex items-center gap-2 min-w-0">
            <span class={[
              "text-[10px] uppercase tracking-wider font-bold px-1.5 py-0.5 rounded",
              if(String.starts_with?(to_string(@task.id), "wt-"),
                do: "bg-primary/15 text-primary",
                else: "bg-amber-400/15 text-amber-400"
              )
            ]}>
              {if(String.starts_with?(to_string(@task.id), "wt-"),
                do: "concoction",
                else: "ingredient"
              )}
            </span>
            <span class="text-base-content/40 text-xs truncate">{@task.id}</span>
          </div>
          <button
            phx-click="deselect-task"
            class="text-base-content/40 hover:text-base-content cursor-pointer p-1.5 -mr-1 rounded hover:bg-base-content/10 transition-colors"
            title="Close (Esc)"
          >
            <span class="text-lg leading-none">&times;</span>
          </button>
        </div>

        <%!-- Scrollable content --%>
        <div class="flex-1 overflow-y-auto">
          <%!-- Merge confirmation bar --%>
          <.merge_confirmation :if={@pending_action} task={@task} pending_action={@pending_action} />

          <%!-- Panel content --%>
          <.task_detail_panel
            task={@task}
            children={@children}
            editing_field={@editing_field}
            working_agent={@working_agent}
            agent_output={@agent_output}
            dev_server={@dev_server}
            has_preview_config={@has_preview_config}
          />
        </div>
      </div>
    </div>
    """
  end

  # --- Merge Confirmation Bar ---

  attr :task, :map, required: true
  attr :pending_action, :any, required: true

  def merge_confirmation(assigns) do
    assigns = assign(assigns, :direct?, match?({:direct_merge, _, _}, assigns.pending_action))

    ~H"""
    <div class="bg-amber-400/10 border-b border-amber-400/30 px-3 py-3">
      <div class="flex items-center gap-3">
        <span class="text-amber-400 text-sm font-apothecary">
          {if @direct?, do: "Merge directly?", else: "Merge this PR?"}
        </span>
        <span class="text-base-content/50 text-xs truncate flex-1">
          "{@task.title}"
        </span>
      </div>
      <div class="flex items-center gap-2 mt-2">
        <button
          phx-click="confirm-merge"
          class="bg-green-500/20 hover:bg-green-500/30 text-green-400 px-3 py-1 rounded text-xs cursor-pointer transition-colors font-bold"
        >
          {if @direct?, do: "Create PR & Merge", else: "Merge PR"}
        </button>
        <button
          phx-click="cancel-merge"
          class="bg-base-content/5 hover:bg-base-content/10 text-base-content/50 px-3 py-1 rounded text-xs cursor-pointer transition-colors"
        >
          Cancel
        </button>
        <span class="text-base-content/30 text-xs ml-auto">m/y/Enter to confirm, Esc to cancel</span>
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
  attr :has_preview_config, :boolean, default: false

  def task_detail_panel(assigns) do
    assigns = assign(assigns, :pr_url, Map.get(assigns.task, :pr_url))

    ~H"""
    <div class="space-y-4 p-4">
      <%!-- Title (inline editable) --%>
      <%= if @editing_field == :title do %>
        <.form for={%{}} phx-submit="save-edit" class="space-y-2">
          <input type="hidden" name="field" value="title" />
          <input
            type="text"
            name="value"
            value={@task.title}
            autofocus
            phx-focus="input-focus"
            phx-blur="input-blur"
            class="bg-transparent border border-primary/30 focus:border-primary outline-none px-3 py-2 text-base w-full rounded"
          />
          <div class="flex items-center gap-2">
            <button
              type="submit"
              class="bg-green-500/15 text-green-400 hover:bg-green-500/25 px-3 py-1 rounded text-xs cursor-pointer transition-colors"
            >
              Save
            </button>
            <button
              type="button"
              phx-click="cancel-edit"
              class="text-base-content/40 hover:text-base-content/60 text-xs cursor-pointer px-2 py-1"
            >
              Cancel
            </button>
          </div>
        </.form>
      <% else %>
        <div
          phx-click="start-edit"
          phx-value-field="title"
          class="text-base font-semibold cursor-pointer hover:bg-base-content/5 px-2 py-1 -mx-2 -mt-1 rounded transition-colors"
        >
          {@task.title}
        </div>
      <% end %>

      <%!-- Status + priority row --%>
      <div class="flex items-center gap-3 flex-wrap">
        <.status_badge status={@task.status} />
        <.priority_controls priority={@task.priority} />
        <span :if={@task.assigned_to} class="text-cyan-400 text-xs">{@task.assigned_to}</span>
      </div>

      <%!-- Description (inline editable) --%>
      <%= if @editing_field == :description do %>
        <.form for={%{}} phx-submit="save-edit" class="space-y-2">
          <input type="hidden" name="field" value="description" />
          <textarea
            name="value"
            rows="4"
            autofocus
            phx-focus="input-focus"
            phx-blur="input-blur"
            class="bg-transparent border border-primary/30 focus:border-primary outline-none px-3 py-2 text-sm w-full rounded resize-none"
          >{@task.description || ""}</textarea>
          <div class="flex items-center gap-2">
            <button
              type="submit"
              class="bg-green-500/15 text-green-400 hover:bg-green-500/25 px-3 py-1 rounded text-xs cursor-pointer transition-colors"
            >
              Save
            </button>
            <button
              type="button"
              phx-click="cancel-edit"
              class="text-base-content/40 hover:text-base-content/60 text-xs cursor-pointer px-2 py-1"
            >
              Cancel
            </button>
          </div>
        </.form>
      <% else %>
        <div
          phx-click="start-edit"
          phx-value-field="description"
          class={[
            "text-sm border-l-2 pl-3 cursor-pointer hover:bg-base-content/5 rounded-r py-1 transition-colors",
            if(@task.description && @task.description != "",
              do: "text-base-content/60 whitespace-pre-wrap border-base-content/15",
              else: "text-base-content/25 border-base-content/10 italic"
            )
          ]}
        >
          {if @task.description && @task.description != "",
            do: @task.description,
            else: "Add description..."}
        </div>
      <% end %>

      <%!-- PR info --%>
      <div :if={@pr_url} class="flex items-center gap-2 text-sm">
        <span class="text-purple-400/60 shrink-0">PR</span>
        <a
          href={@pr_url}
          target="_blank"
          class="text-purple-400 hover:text-purple-300 truncate text-xs"
        >
          {@pr_url}
        </a>
      </div>

      <%!-- Actions --%>
      <div class="flex items-center gap-2 flex-wrap">
        <button
          phx-click="claim"
          class="border border-cyan-400/30 text-cyan-400 hover:bg-cyan-400/10 cursor-pointer py-1.5 px-3 rounded text-xs transition-colors"
        >
          Claim
        </button>
        <button
          phx-click="requeue"
          class="border border-yellow-400/30 text-yellow-400 hover:bg-yellow-400/10 cursor-pointer py-1.5 px-3 rounded text-xs transition-colors"
        >
          Requeue <span class="hidden sm:inline text-base-content/30 ml-1">q</span>
        </button>
        <button
          phx-click="close"
          class="border border-red-400/30 text-red-400 hover:bg-red-400/10 cursor-pointer py-1.5 px-3 rounded text-xs transition-colors"
        >
          Close <span class="hidden sm:inline text-base-content/30 ml-1">x</span>
        </button>
        <button
          :if={@task.status == "pr_open"}
          phx-click="merge-pr"
          class="border border-green-400/30 text-green-400 hover:bg-green-400/10 cursor-pointer py-1.5 px-3 rounded text-xs transition-colors font-bold"
        >
          Merge <span class="hidden sm:inline text-base-content/30 ml-1">m</span>
        </button>
        <button
          :if={@task.status == "brew_done"}
          phx-click="direct-merge"
          class="border border-green-400/30 text-green-400 hover:bg-green-400/10 cursor-pointer py-1.5 px-3 rounded text-xs transition-colors font-bold"
        >
          Merge <span class="hidden sm:inline text-base-content/30 ml-1">m</span>
        </button>
        <button
          :if={@task.status == "brew_done"}
          phx-click="promote-to-assaying"
          class="border border-purple-400/30 text-purple-400 hover:bg-purple-400/10 cursor-pointer py-1.5 px-3 rounded text-xs transition-colors"
        >
          Create PR <span class="hidden sm:inline text-base-content/30 ml-1">p</span>
        </button>
      </div>

      <%!-- Ingredients section --%>
      <div class="space-y-2">
        <.section label="ingredients" />
        <div class="space-y-0.5">
          <.child_task_row :for={child <- @children} task={child} />
          <div :if={@children == []} class="text-base-content/25 px-3 py-1 text-xs italic">
            No ingredients yet
          </div>
        </div>
        <.form
          for={%{}}
          phx-submit="create-child"
          class="flex items-center gap-2 px-3"
          id="create-child-form"
        >
          <input
            type="text"
            name="title"
            id="child-input"
            placeholder="Add ingredient..."
            phx-focus="input-focus"
            phx-blur="input-blur"
            autocomplete="off"
            class="bg-transparent border border-base-content/15 focus:border-primary outline-none px-3 py-1.5 text-sm flex-1 min-w-0 rounded"
          />
          <button
            type="submit"
            class="bg-base-content/5 hover:bg-base-content/10 text-base-content/50 hover:text-base-content/70 px-2.5 py-1.5 rounded text-xs cursor-pointer transition-colors shrink-0"
          >
            +
          </button>
        </.form>
      </div>

      <%!-- Notes --%>
      <div :if={@task.notes && @task.notes != ""} class="space-y-2">
        <div class="flex items-center gap-2">
          <div class="flex-1"><.section label="notes" /></div>
          <.copy_button target="#task-notes" />
        </div>
        <div
          id="task-notes"
          class="text-base-content/50 whitespace-pre-wrap text-xs px-3 py-2 bg-base-content/3 rounded"
        >
          {@task.notes}
        </div>
      </div>

      <%!-- Dependencies section --%>
      <div class="space-y-2">
        <.section label="blocked by" />
        <div :for={b <- @task.blockers} class="flex items-center gap-2 px-3 text-sm">
          <.link patch={~p"/?task=#{b}"} class="text-red-400 hover:text-red-300">{b}</.link>
          <button
            phx-click="remove-dep"
            phx-value-blocker_id={b}
            class="text-base-content/25 hover:text-red-400 cursor-pointer p-0.5"
          >
            &times;
          </button>
        </div>
        <div :if={@task.blockers == []} class="text-base-content/25 px-3 text-xs italic">None</div>
        <.form for={%{}} phx-submit="add-dep" class="flex items-center gap-2 px-3" id="add-dep-form">
          <input
            type="text"
            name="dep_id"
            placeholder="Add dependency ID..."
            phx-focus="input-focus"
            phx-blur="input-blur"
            autocomplete="off"
            class="bg-transparent border border-base-content/15 focus:border-primary outline-none px-3 py-1.5 text-sm flex-1 min-w-0 rounded"
          />
          <button
            type="submit"
            class="bg-base-content/5 hover:bg-base-content/10 text-base-content/50 hover:text-base-content/70 px-2.5 py-1.5 rounded text-xs cursor-pointer transition-colors shrink-0"
          >
            +
          </button>
        </.form>
      </div>

      <%!-- Blocks section --%>
      <div :if={@task.dependents != []} class="space-y-2">
        <.section label="blocks" />
        <div :for={d <- @task.dependents} class="px-3 text-sm">
          <.link patch={~p"/?task=#{d}"} class="text-cyan-400 hover:text-cyan-300">{d}</.link>
        </div>
      </div>

      <%!-- MCP servers section (concoctions only) --%>
      <div :if={String.starts_with?(to_string(@task.id), "wt-")} class="space-y-2">
        <.section label="mcp servers" />
        <div class="space-y-1">
          <%= for {name, config} <- Map.get(@task, :mcp_servers) || %{} do %>
            <div class="flex items-center gap-2 px-3 group">
              <span class="text-sm text-violet-400">{name}</span>
              <span class="text-xs text-base-content/30 truncate flex-1">
                {config["url"] || config["command"] || "configured"}
              </span>
              <button
                phx-click="remove-mcp"
                phx-value-name={name}
                class="text-base-content/25 hover:text-red-400 cursor-pointer p-0.5 opacity-0 group-hover:opacity-100 transition-opacity"
              >
                &times;
              </button>
            </div>
          <% end %>
          <div
            :if={Map.get(@task, :mcp_servers) == nil or Map.get(@task, :mcp_servers) == %{}}
            class="text-base-content/25 px-3 text-xs italic"
          >
            No extra MCPs — project-level MCPs are inherited automatically
          </div>
        </div>
        <.form
          for={%{}}
          phx-submit="add-mcp"
          class="flex items-center gap-2 px-3"
          id="add-mcp-form"
        >
          <input
            type="text"
            name="mcp_name"
            placeholder="Name (e.g. figma)"
            phx-focus="input-focus"
            phx-blur="input-blur"
            autocomplete="off"
            class="bg-transparent border border-base-content/15 focus:border-primary outline-none px-3 py-1.5 text-sm w-24 rounded"
          />
          <input
            type="text"
            name="mcp_url"
            placeholder="URL or command"
            phx-focus="input-focus"
            phx-blur="input-blur"
            autocomplete="off"
            class="bg-transparent border border-base-content/15 focus:border-primary outline-none px-3 py-1.5 text-sm flex-1 min-w-0 rounded"
          />
          <button
            type="submit"
            class="bg-base-content/5 hover:bg-base-content/10 text-base-content/50 hover:text-base-content/70 px-2.5 py-1.5 rounded text-xs cursor-pointer transition-colors shrink-0"
          >
            +
          </button>
        </.form>
      </div>

      <%!-- Preview & shortcuts section --%>
      <div :if={String.starts_with?(to_string(@task.id), "wt-")} class="space-y-2">
        <.section label="preview" />
        <.dev_server_detail
          task_id={@task.id}
          dev_server={@dev_server}
          has_preview_config={@has_preview_config}
        />
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

      <%!-- Bottom spacer for mobile scroll --%>
      <div class="h-4 sm:h-0"></div>
    </div>
    """
  end

  # --- Section header ---

  attr :label, :string, required: true

  def section(assigns) do
    ~H"""
    <div class="flex items-center gap-2 text-base-content/30 text-[11px] uppercase tracking-widest select-none font-apothecary">
      <span>{@label}</span>
      <span class="flex-1 border-b border-base-content/8"></span>
    </div>
    """
  end

  # --- Child task row ---

  attr :task, :map, required: true

  def child_task_row(assigns) do
    ~H"""
    <.link
      patch={~p"/?task=#{@task.id}"}
      class="flex items-center gap-2 px-3 py-1.5 hover:bg-base-content/5 cursor-pointer rounded transition-colors"
    >
      <span class={["w-10 shrink-0 uppercase text-xs font-bold", status_color(@task.status)]}>
        {status_abbrev(@task.status)}
      </span>
      <span class="text-base-content/30 shrink-0 text-xs">{@task.id}</span>
      <span class="truncate text-sm">{@task.title}</span>
    </.link>
    """
  end

  # --- Agent output panel ---

  attr :working_agent, :map, required: true
  attr :agent_output, :list, default: []

  def agent_output_panel(assigns) do
    ~H"""
    <div class="space-y-1">
      <div class="flex items-center gap-2">
        <div class="flex-1">
          <.section label={"alchemist-#{@working_agent.id} output"} />
        </div>
        <.copy_button :if={@agent_output != []} target="#agent-output" />
      </div>
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
  attr :has_preview_config, :boolean, default: false

  defp dev_server_detail(%{dev_server: nil, has_preview_config: true} = assigns) do
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

  defp dev_server_detail(%{dev_server: nil, has_preview_config: false} = assigns) do
    ~H"""
    <div class="px-3 text-xs space-y-1">
      <span class="text-base-content/30">no config found</span>
      <p class="text-base-content/40">
        Add <code class="text-amber-400/70">.apothecary/preview.yml</code>
        to your project root to enable preview.
      </p>
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
        <.copy_button :if={@dev_server.error || @dev_server.output != []} target="#dev-error-output" />
      </div>
      <div id="dev-error-output">
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
    </div>
    """
  end

  defp dev_server_detail(%{has_preview_config: true} = assigns) do
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

  defp dev_server_detail(assigns) do
    ~H"""
    <div class="px-3 text-xs space-y-1">
      <span class="text-base-content/30">no config found</span>
      <p class="text-base-content/40">
        Add <code class="text-amber-400/70">.apothecary/preview.yml</code>
        to your project root to enable preview.
      </p>
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

  attr :priority, :any, default: nil

  def priority_controls(assigns) do
    ~H"""
    <div class="flex items-center gap-0.5">
      <button
        phx-click="change-priority"
        phx-value-dir="up"
        disabled={(@priority || 3) <= 0}
        class={[
          "px-1.5 py-0.5 text-sm cursor-pointer rounded transition-colors",
          if((@priority || 3) <= 0,
            do: "text-base-content/15",
            else:
              "text-base-content/40 hover:text-base-content hover:bg-base-content/10 active:bg-base-content/20"
          )
        ]}
        title="Higher priority (↑)"
      >
        ▲
      </button>
      <span class={["text-sm min-w-6 text-center", priority_color(@priority || 3)]}>
        P{@priority || 3}
      </span>
      <button
        phx-click="change-priority"
        phx-value-dir="down"
        disabled={(@priority || 3) >= 4}
        class={[
          "px-1.5 py-0.5 text-sm cursor-pointer rounded transition-colors",
          if((@priority || 3) >= 4,
            do: "text-base-content/15",
            else:
              "text-base-content/40 hover:text-base-content hover:bg-base-content/10 active:bg-base-content/20"
          )
        ]}
        title="Lower priority (↓)"
      >
        ▼
      </button>
    </div>
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
          <div id="diff-error-text" class="text-red-400 text-sm">{@diff.error}</div>
          <div class="flex items-center justify-center gap-3">
            <.copy_button target="#diff-error-text" />
            <span class="text-base-content/30 text-xs">press esc to close</span>
          </div>
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
            <div class="text-emerald-400 mb-1">lanes & tabs</div>
            <.hk key="1" desc="jump to stockroom" />
            <.hk key="2" desc="jump to concocting" />
            <.hk key="3" desc="jump to assaying" />
            <.hk key="4" desc="jump to bottled" />
            <.hk key="w" desc="workbench tab" />
            <.hk key="e" desc="recurring concoctions" />
          </div>

          <div class="space-y-1">
            <div class="text-emerald-400 mb-1">actions</div>
            <.hk key="s" desc="start/stop concocting" />
            <.hk key="+/-" desc="alchemist count" />
            <.hk key="r" desc="refresh" />
            <.hk key="R" desc="requeue orphans" />
            <.hk key="d" desc="view diff" />
            <.hk key="D" desc="toggle preview" />
            <.hk key="?" desc="toggle this help" />
          </div>

          <div :if={@has_selected_task} class="space-y-1">
            <div class="text-emerald-400 mb-1">when inspecting</div>
            <.hk key="↑/↓" desc="change priority" />
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
  defp page_label(:agent), do: "ALCHEMIST"
  defp page_label(_), do: ""

  # --- Helper functions ---

  defp status_abbrev("open"), do: "RDY"
  defp status_abbrev("ready"), do: "RDY"
  defp status_abbrev("in_progress"), do: "WIP"
  defp status_abbrev("claimed"), do: "WIP"
  defp status_abbrev("brew_done"), do: "BREW"
  defp status_abbrev("pr_open"), do: "PR"
  defp status_abbrev("revision_needed"), do: "REV"
  defp status_abbrev("merged"), do: "MRG"
  defp status_abbrev("done"), do: "DONE"
  defp status_abbrev("closed"), do: "DONE"
  defp status_abbrev("blocked"), do: "BLK"
  defp status_abbrev(nil), do: "???"
  defp status_abbrev(_), do: "???"

  defp lane_color("ready"), do: "text-emerald-400"
  defp lane_color("blocked"), do: "text-emerald-400"
  defp lane_color("running"), do: "text-amber-400"
  defp lane_color("pr"), do: "text-purple-400"
  defp lane_color("done"), do: "text-green-400/70"
  defp lane_color(_), do: "text-base-content/50"

  defp status_color("open"), do: "text-emerald-400"
  defp status_color("ready"), do: "text-emerald-400"
  defp status_color("in_progress"), do: "text-amber-400"
  defp status_color("claimed"), do: "text-amber-400"
  defp status_color("brew_done"), do: "text-amber-400/70"
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

  defp group_badge_label("running"), do: "CONCOCTING"
  defp group_badge_label("ready"), do: "STOCKED"
  defp group_badge_label("blocked"), do: "MISSING"
  defp group_badge_label("pr"), do: "ASSAYING"
  defp group_badge_label("done"), do: "BOTTLED"
  defp group_badge_label(_), do: ""

  # --- Tab Navigation ---

  attr :active_tab, :atom, required: true

  def tab_navigation(assigns) do
    ~H"""
    <div class="flex items-center gap-1 min-w-0">
      <button
        phx-click="switch-tab"
        phx-value-tab="workbench"
        class={[
          "px-2 sm:px-3 py-1 text-xs font-apothecary tracking-wide rounded transition-colors cursor-pointer whitespace-nowrap",
          if(@active_tab == :workbench,
            do: "text-base-content bg-base-content/10 font-bold",
            else: "text-base-content/40 hover:text-base-content/70 hover:bg-base-content/5"
          )
        ]}
      >
        Workbench
      </button>
      <button
        phx-click="switch-tab"
        phx-value-tab="oracle"
        class={[
          "px-2 sm:px-3 py-1 text-xs font-apothecary tracking-wide rounded transition-colors cursor-pointer whitespace-nowrap",
          if(@active_tab == :oracle,
            do: "text-base-content bg-base-content/10 font-bold",
            else: "text-base-content/40 hover:text-base-content/70 hover:bg-base-content/5"
          )
        ]}
      >
        Oracle
      </button>
      <button
        phx-click="switch-tab"
        phx-value-tab="recipes"
        class={[
          "px-2 sm:px-3 py-1 text-xs font-apothecary tracking-wide rounded transition-colors cursor-pointer whitespace-nowrap",
          if(@active_tab == :recipes,
            do: "text-base-content bg-base-content/10 font-bold",
            else: "text-base-content/40 hover:text-base-content/70 hover:bg-base-content/5"
          )
        ]}
      >
        <span class="sm:hidden">Recipes</span>
        <span class="hidden sm:inline">Recurring Concoctions</span>
      </button>
    </div>
    """
  end

  # --- Oracle View (Questions) ---

  attr :questions, :list, required: true
  attr :agents, :list, default: []

  def oracle_view(assigns) do
    active_wt_ids =
      assigns.agents
      |> Enum.flat_map(fn a ->
        if a.current_concoction, do: [to_string(a.current_concoction.id)], else: []
      end)
      |> MapSet.new()

    sorted =
      assigns.questions
      |> Enum.sort_by(fn q -> q.created_at || "" end, :desc)

    assigns = assign(assigns, sorted: sorted, active_wt_ids: active_wt_ids)

    ~H"""
    <div class="max-w-2xl mx-auto pt-3 sm:pt-6 pb-2 px-1 sm:px-0">
      <h2 class="text-base-content/50 text-lg font-semibold mb-2 font-apothecary">
        Ask the Oracle
      </h2>
      <p class="text-base-content/30 text-xs mb-3">
        Type <code class="text-primary/60">? your question</code>
        in the input on the Workbench tab to ask about the codebase.
      </p>
    </div>
    <div class="max-w-2xl mx-auto px-1 sm:px-0 space-y-3 pb-8">
      <%= if @sorted == [] do %>
        <div class="py-8 text-center text-base-content/30 text-sm">
          No questions yet.
        </div>
      <% end %>
      <div :for={q <- @sorted} class="border border-base-content/10 rounded-lg overflow-hidden">
        <div class="px-4 py-3 flex items-start gap-3">
          <.question_status_dot status={q.status} active={MapSet.member?(@active_wt_ids, q.id)} />
          <div class="flex-1 min-w-0">
            <div class="text-sm font-medium text-base-content/80">{q.title}</div>
            <div class="text-xs text-base-content/30 mt-0.5">{q.id}</div>
          </div>
        </div>
        <%= if q.notes && q.notes != "" do %>
          <div class="border-t border-base-content/10 px-4 py-3 bg-base-200/50">
            <div class="text-xs text-base-content/60 whitespace-pre-wrap font-mono leading-relaxed">
              {format_question_answer(q.notes)}
            </div>
          </div>
        <% end %>
      </div>
    </div>
    """
  end

  defp question_status_dot(assigns) do
    ~H"""
    <%= cond do %>
      <% @active -> %>
        <span class="mt-1 flex h-2.5 w-2.5 shrink-0">
          <span class="absolute inline-flex h-2.5 w-2.5 animate-ping rounded-full bg-amber-400 opacity-75">
          </span>
          <span class="relative inline-flex h-2.5 w-2.5 rounded-full bg-amber-500"></span>
        </span>
      <% @status == "done" -> %>
        <span class="mt-1 h-2.5 w-2.5 rounded-full bg-emerald-500 shrink-0"></span>
      <% true -> %>
        <span class="mt-1 h-2.5 w-2.5 rounded-full bg-base-content/20 shrink-0"></span>
    <% end %>
    """
  end

  defp format_question_answer(notes) do
    # Extract the answer portion from notes (after "Answer:" marker)
    case String.split(notes, "Answer:\n", parts: 2) do
      [_before, answer] -> String.trim(answer)
      _ -> notes
    end
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
            Recurring Concoctions
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
            Create a recipe to schedule recurring concoctions
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
