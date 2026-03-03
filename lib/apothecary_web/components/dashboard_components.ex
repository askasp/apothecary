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

  def top_bar(assigns) do
    ~H"""
    <div class="flex items-center justify-between px-3 py-2" style="font-size: var(--font-size-sm);">
      <div class="flex items-center gap-0 min-w-0">
        <%= if @selected_task_id && @selected_task do %>
          <span style="color: var(--accent);">apothecary</span>
          <span style="color: var(--dim);">
            &nbsp;/ {if @current_project, do: @current_project.name, else: "—"}
          </span>
          <span style="color: var(--concocting);">
            &nbsp;/ {@selected_task_id}
          </span>
        <% else %>
          <.link navigate={~p"/"} style="color: var(--accent); text-decoration: none;">
            apothecary
          </.link>
          <%= if @current_project do %>
            <span style="color: var(--dim);">&nbsp;/ </span>
            <div class="relative inline-block" id="project-dropdown" phx-hook=".ProjectDropdown">
              <button
                phx-click={toggle_dropdown()}
                type="button"
                class="cursor-pointer"
                style="color: var(--dim);"
              >
                {@current_project.name}
              </button>
              <div
                id="project-dropdown-menu"
                class="hidden absolute left-0 top-full mt-1 z-50 py-1"
                style="background: var(--surface); border: 1px solid var(--border); min-width: 200px;"
              >
                <.link
                  :for={project <- @projects}
                  navigate={~p"/projects/#{project.id}"}
                  class="block px-3 py-1.5 cursor-pointer"
                  style={"color: #{if @current_project && @current_project.id == project.id, do: "var(--text)", else: "var(--dim)"}; font-size: var(--font-size-sm); text-decoration: none;"}
                >
                  {project.name}
                </.link>
                <div style="border-top: 1px solid var(--border); margin: 4px 0;" />
                <button
                  phx-click="show-add-project"
                  class="block w-full text-left px-3 py-1.5 cursor-pointer"
                  style="color: var(--muted); font-size: var(--font-size-sm);"
                >
                  open project
                </button>
                <button
                  phx-click="show-new-project"
                  class="block w-full text-left px-3 py-1.5 cursor-pointer"
                  style="color: var(--muted); font-size: var(--font-size-sm);"
                >
                  new project
                </button>
              </div>
            </div>
          <% else %>
            <span style="color: var(--muted);">&nbsp;/ select a project</span>
          <% end %>
        <% end %>
      </div>
      <div :if={@current_project && !(@selected_task_id && @selected_task)} class="flex items-center gap-3">
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
      <div :if={@selected_task_id && @selected_task}>
        <span style="color: var(--muted); font-size: var(--font-size-xs);">esc back</span>
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
      in: {"ease-out duration-100", "opacity-0", "opacity-100"},
      out: {"ease-in duration-75", "opacity-100", "opacity-0"}
    )
  end

  # ── Settings Line ────────────────────────────────────────

  attr :target_count, :integer, default: 1
  attr :auto_pr, :boolean, default: false
  attr :swarm_status, :atom, default: :paused
  attr :dev_server, :any, default: nil
  attr :port, :integer, default: 4005

  def settings_line(assigns) do
    port =
      case assigns.dev_server do
        %{ports: [%{port: p} | _]} -> p
        _ -> assigns.port
      end

    assigns = assign(assigns, :display_port, port)

    ~H"""
    <div class="px-3 py-1" style="font-size: var(--font-size-xs);">
      <span style="color: var(--dim);">alchemists:</span>
      <span style="color: var(--text);">&nbsp;{@target_count}</span>
      <span style="color: var(--border);">&nbsp;&middot;&nbsp;</span>
      <span style="color: var(--dim);">auto-pr:</span>
      <span style={"color: #{if @auto_pr, do: "var(--accent)", else: "var(--text)"};"}>
        &nbsp;{if @auto_pr, do: "on", else: "off"}
      </span>
      <span style="color: var(--border);">&nbsp;&middot;&nbsp;</span>
      <span style="color: var(--dim);">main</span>
      <span style="color: var(--text);">&nbsp;:{@display_port}</span>
    </div>
    """
  end

  # ── Concoction Input ─────────────────────────────────────

  attr :input_focused, :boolean, default: false

  def concoction_input(assigns) do
    ~H"""
    <div class="px-3 py-2">
      <div class="relative">
        <textarea
          id="primary-input"
          rows="1"
          phx-hook="TextareaSubmit"
          phx-focus="input-focus"
          phx-blur="input-blur"
          autocomplete="off"
          class="moonlight-input w-full resize-none"
          style="min-height: 32px; max-height: 120px;"
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

    assigns =
      assigns
      |> assign(:concocting, concocting)
      |> assign(:assaying, assaying)
      |> assign(:queued, queued)
      |> assign(:bottled, bottled)

    ~H"""
    <div class="px-3 py-2">
      <%!-- Concocting group --%>
      <.tree_group
        :if={@concocting != []}
        label="concocting"
        count={length(@concocting)}
        color="var(--concocting)"
        entries={@concocting}
        dot="◉"
        dot_class="dot-pulse"
        title_color="var(--text)"
        card_ids={@card_ids}
        selected_card={@selected_card}
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

  defp tree_group(assigns) do
    ~H"""
    <div style={"opacity: #{@opacity};"}>
      <div :if={@label} class="py-1" style={"color: #{@color}; font-size: var(--font-size-sm);"}>
        {@label} ({@count})
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
          <div
            style={"background: #{if selected?, do: "var(--surface)", else: "transparent"};"}
            class="cursor-pointer"
            phx-click="select-task"
            phx-value-id={wt.id}
            data-card-id={wt.id}
            data-selected={if(selected?, do: "true")}
          >
            <%!-- Tree line + dot + title --%>
            <div class="flex items-baseline gap-1 py-0.5 px-1">
              <span class="tree-char">{if last?, do: "└─", else: "├─"}</span>
              <span class={@dot_class} style={"color: #{@color};"}>{@dot}</span>
              <span style={"color: #{@title_color};"}>{wt.title || wt.id}</span>
            </div>
            <%!-- Metadata line --%>
            <div class="flex items-center gap-1 pl-7 pb-1" style="color: var(--muted); font-size: var(--font-size-xs);">
              <span>{wt.id}</span>
              <span :if={total_count > 0}>
                &middot; {done_count}/{total_count}
              </span>
              <span :if={port}>
                &middot; :{port}
              </span>
            </div>
          </div>
          <%!-- Connector line between entries (not after last) --%>
          <div :if={!last?} class="tree-char pl-1" style="font-size: var(--font-size-sm);">│</div>
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
    <div class="px-3 py-3 scroll-main overflow-y-auto flex-1">
      <%!-- 1. Title + Status --%>
      <div class="mb-4">
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
              style="font-size: var(--font-size-title);"
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
            style="font-size: var(--font-size-title); color: var(--text);"
          >
            {@task.title}
          </div>
        <% end %>
        <div class="flex items-center gap-2 mt-1" style="font-size: var(--font-size-xs);">
          <span style={"color: #{@status_color};"}>{@status_dot}</span>
          <span style={"color: #{@status_color};"}>{@status_group}</span>
          <span :if={@brewer_label} style="color: var(--dim);">&middot; {@brewer_label}</span>
          <span :if={@time_ago} style="color: var(--muted);">&middot; {@time_ago}</span>
        </div>
      </div>

      <%!-- 2. Actions --%>
      <div class="flex items-center gap-3 mb-4" style="font-size: var(--font-size-sm);">
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
      <div class="mb-4">
        <div class="section-header mb-2">INGREDIENTS</div>
        <%= if @children == [] do %>
          <div style="color: var(--muted); font-size: var(--font-size-sm);">none</div>
        <% else %>
          <div :for={child <- @children} class="flex items-center gap-2 py-0.5" style="font-size: var(--font-size-sm);">
            <span style={"color: #{if child.status in ["done", "closed"], do: "var(--accent)", else: "var(--concocting)"};"}>
              {if child.status in ["done", "closed"], do: "✓", else: "◌"}
            </span>
            <span style={"color: #{if child.status in ["done", "closed"], do: "var(--dim)", else: "var(--text)"};"}>
              {child.title}
            </span>
            <span class="ml-auto" style="color: var(--muted); font-size: var(--font-size-xs);">
              {child.id}
            </span>
          </div>
        <% end %>
      </div>

      <%!-- 4. GIT --%>
      <div :if={@last_commit || @git_changes} class="mb-4">
        <div class="section-header mb-2">GIT</div>
        <div :if={@last_commit} style="color: var(--dim); font-size: var(--font-size-sm);" class="mb-1">
          <span style="color: var(--muted);">{String.slice(@last_commit.hash || "", 0..6)}</span>
          &nbsp;{@last_commit.message}
        </div>
        <div :if={@git_changes} style="font-size: var(--font-size-xs);">
          <div :for={file <- @git_changes.files || []} class="flex items-center gap-2 py-0.5">
            <span style="color: var(--muted);">{file.path}</span>
            <span :if={file.additions > 0} style="color: var(--accent);">+{file.additions}</span>
            <span :if={file.deletions > 0} style="color: var(--error);">-{file.deletions}</span>
          </div>
        </div>
        <div class="mt-1">
          <span class="action-text" phx-click="view-diff" phx-value-id={@task.id}>d view diff</span>
        </div>
      </div>

      <%!-- 5. PREVIEW --%>
      <div :if={@dev_server || @has_preview_config} class="mb-4">
        <div class="section-header mb-2">PREVIEW</div>
        <%= cond do %>
          <% @dev_server && @dev_server.status == :running -> %>
            <% port = List.first(@dev_server.ports || []) %>
            <span class="action-text" phx-click="open-preview" phx-value-id={@task.id}>
              p open :{port && port.port}
            </span>
            <span style="color: var(--border);">&nbsp;&middot;&nbsp;</span>
            <span class="action-text" phx-click="view-diff" phx-value-id={@task.id}>d view diff</span>
          <% @dev_server && @dev_server.status == :starting -> %>
            <span style="color: var(--concocting); font-size: var(--font-size-sm);">starting...</span>
          <% @has_preview_config -> %>
            <span class="action-text" phx-click="start-dev" phx-value-id={@task.id}>
              start preview
            </span>
          <% true -> %>
            <span style="color: var(--muted); font-size: var(--font-size-sm);">no preview config</span>
        <% end %>
      </div>

      <%!-- 6. OUTPUT --%>
      <div :if={@agent_output != []} class="mb-4">
        <div class="section-header mb-2">
          OUTPUT &middot; {length(@agent_output)} lines
        </div>
        <.agent_output_panel output={@agent_output} />
      </div>

      <%!-- 7. PR link --%>
      <div :if={@pr_url} class="mb-4">
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
      <div :if={@task.description && @task.description != ""} class="mb-4">
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
      <div :if={@task.notes && @task.notes != ""} class="mb-4">
        <div class="section-header mb-2">NOTES</div>
        <div
          id="task-notes-content"
          style="color: var(--dim); font-size: var(--font-size-xs); white-space: pre-wrap;"
        >
          {@task.notes}
        </div>
        <.copy_button target="#task-notes-content" />
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
      <%= if @selected_task_id && @selected_task do %>
        <div class="flex items-center gap-2">
          <span>esc back</span>
          <span style="color: var(--border);">&middot;</span>
          <span>c pr</span>
          <span style="color: var(--border);">&middot;</span>
          <span>m merge</span>
          <span style="color: var(--border);">&middot;</span>
          <span>d diff</span>
        </div>
        <div>
          <span style={"color: #{group_color(task_status_group(@selected_task))};"}>
            {task_status_group(@selected_task)}
          </span>
        </div>
      <% else %>
        <div class="flex items-center gap-2">
          <span>j/k nav</span>
          <span style="color: var(--border);">&middot;</span>
          <span>enter expand</span>
          <span style="color: var(--border);">&middot;</span>
          <span>s concoct</span>
          <span style="color: var(--border);">&middot;</span>
          <span>? help</span>
        </div>
        <div class="flex items-center gap-2">
          <span style="color: var(--concocting);">◉{@running_count}</span>
          <span style="color: var(--assaying);">◎{@pr_count}</span>
          <span style="color: var(--muted);">○{@queued_count}</span>
          <span style="color: var(--bottled);">●{@done_count}</span>
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

    sorted = Enum.sort_by(assigns.questions, fn q -> q.created_at || "" end, :desc)
    assigns = assign(assigns, sorted: sorted, active_wt_ids: active_wt_ids)

    ~H"""
    <div class="px-3 py-3">
      <div class="section-header mb-2">ORACLE</div>
      <div style="color: var(--muted); font-size: var(--font-size-xs);" class="mb-3">
        type ? in the input to ask about the codebase
      </div>
      <%= if @sorted == [] do %>
        <div style="color: var(--muted); font-size: var(--font-size-sm);" class="py-6">
          no questions yet
        </div>
      <% end %>
      <div :for={q <- @sorted} class="mb-3 p-3" style="border: 1px solid var(--border);">
        <div class="flex items-start gap-2">
          <span style={"color: #{cond do
            MapSet.member?(@active_wt_ids, q.id) -> "var(--concocting)"
            q.status == "done" -> "var(--accent)"
            true -> "var(--muted)"
          end};"}>
            {cond do
              MapSet.member?(@active_wt_ids, q.id) -> "◉"
              q.status == "done" -> "●"
              true -> "○"
            end}
          </span>
          <div class="flex-1">
            <div style="color: var(--text); font-size: var(--font-size-sm);">{q.title}</div>
            <div style="color: var(--muted); font-size: var(--font-size-xs);">{q.id}</div>
          </div>
        </div>
        <%= if q.notes && q.notes != "" do %>
          <div class="mt-2 pt-2" style="border-top: 1px solid var(--border); color: var(--dim); font-size: var(--font-size-xs); white-space: pre-wrap;">
            {format_question_answer(q.notes)}
          </div>
        <% end %>
      </div>
    </div>
    """
  end

  defp format_question_answer(notes) do
    case String.split(notes, "Answer:\n", parts: 2) do
      [_before, answer] -> String.trim(answer)
      _ -> notes
    end
  end

  # ── Recipe List ──────────────────────────────────────────

  attr :recipes, :list, required: true
  attr :show_recipe_form, :boolean, default: false
  attr :recipe_form, :any, default: nil
  attr :editing_recipe_id, :string, default: nil

  def recipe_list(assigns) do
    ~H"""
    <div class="px-3 py-3">
      <div class="flex items-center justify-between mb-3">
        <div class="section-header">RECURRING CONCOCTIONS</div>
        <button
          :if={!@show_recipe_form}
          phx-click="show-recipe-form"
          class="action-text"
        >
          + new recipe
        </button>
      </div>

      <.recipe_form :if={@show_recipe_form} form={@recipe_form} editing_id={@editing_recipe_id} />

      <%= if @recipes == [] and !@show_recipe_form do %>
        <div style="color: var(--muted); font-size: var(--font-size-sm);" class="py-6">
          no recipes yet
        </div>
      <% else %>
        <.recipe_card :for={recipe <- @recipes} recipe={recipe} />
      <% end %>
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

  attr :recipe, :any, required: true

  defp recipe_card(assigns) do
    ~H"""
    <div class="mb-2 p-3" style={"border: 1px solid var(--border); opacity: #{if @recipe.enabled, do: "1", else: "0.5"};"}>
      <div class="flex items-start justify-between gap-3">
        <div class="flex-1 min-w-0">
          <div class="flex items-center gap-2">
            <span style="color: var(--text); font-size: var(--font-size-sm);">{@recipe.title}</span>
            <span style={"color: #{if @recipe.enabled, do: "var(--accent)", else: "var(--muted)"}; font-size: var(--font-size-xs);"}>
              {if(@recipe.enabled, do: "active", else: "paused")}
            </span>
          </div>
          <div :if={@recipe.description} class="mt-1" style="color: var(--muted); font-size: var(--font-size-xs);">
            {@recipe.description}
          </div>
          <div class="flex items-center gap-3 mt-1" style="font-size: var(--font-size-xs); color: var(--muted);">
            <span style="color: var(--dim);">{@recipe.schedule}</span>
            <span :if={@recipe.next_run_at}>next: {format_relative_time(@recipe.next_run_at)}</span>
          </div>
        </div>
        <div class="flex items-center gap-1 shrink-0">
          <button phx-click="toggle-recipe" phx-value-id={@recipe.id} class="action-text">
            {if(@recipe.enabled, do: "pause", else: "resume")}
          </button>
          <button phx-click="edit-recipe" phx-value-id={@recipe.id} class="action-text">edit</button>
          <button phx-click="delete-recipe" phx-value-id={@recipe.id} class="action-text" data-confirm="Delete this recipe?">
            delete
          </button>
        </div>
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
