defmodule ApothecaryWeb.DashboardLive do
  use ApothecaryWeb, :live_view

  alias Apothecary.{
    Brewer,
    DevServer,
    DiffParser,
    FileTree,
    Git,
    Worktrees,
    WorktreeManager,
    Dispatcher,
    Projects
  }

  @pubsub Apothecary.PubSub

  @group_order ~w(running ready blocked pr done discarded)

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      Worktrees.subscribe()
      Worktrees.subscribe_recipes()
      Dispatcher.subscribe()
      DevServer.subscribe()
      Projects.subscribe()
    end

    dispatcher_status = Dispatcher.status()
    agents = enrich_agents_with_pids(dispatcher_status.agents)
    dev_servers = DevServer.list_servers()

    if connected?(socket) do
      subscribe_to_agents(agents)
    end

    projects = Projects.list_active()

    socket =
      socket
      |> assign(:page_title, "Dashboard")
      |> assign(:projects, projects)
      |> assign(:current_project, nil)
      |> assign(:swarm_status, :paused)
      |> assign(:target_count, 1)
      |> assign(:active_count, 0)
      |> assign(:agents, agents)
      |> assign(:dispatcher_projects, dispatcher_status[:projects] || %{})
      |> assign(:show_help, false)
      |> assign(:input_focused, false)
      |> assign(:dev_servers, dev_servers)
      |> assign(:has_preview_config, false)
      |> assign(:has_project_preview_config, false)
      |> assign(:collapsed_done, true)
      |> assign(:collapsed_discarded, true)
      |> assign(:selected_card, -1)
      # Panel state
      |> assign(:selected_task_id, nil)
      |> assign(:selected_task, nil)
      |> assign(:children, [])
      |> assign(:editing_field, nil)
      |> assign(:editing_child_id, nil)
      |> assign(:follow_up_question_id, nil)
      |> assign(:working_agent, nil)
      |> assign(:agent_output, [])
      |> assign(:diff_view, nil)
      |> assign(:show_preview, false)
      |> assign(:preview_port, nil)
      |> assign(:show_preview_logs, false)
      |> assign(:pending_action, nil)
      |> assign(:loading_action, nil)
      # Tab navigation
      |> assign(:active_tab, :workbench)
      # Recipe state
      |> assign(:recipes, Worktrees.list_recipes())
      |> assign(:show_recipe_form, false)
      |> assign(
        :recipe_form,
        to_form(%{"title" => "", "description" => "", "schedule" => "", "priority" => "3"},
          as: :recipe
        )
      )
      |> assign(:editing_recipe_id, nil)
      |> assign(:project_files, load_project_files(nil))
      # Auto PR
      |> assign(:auto_pr, Git.auto_pr?())
      |> assign(:gh_available, Git.gh_available?())
      # Project selection (inline landing)
      |> assign(:show_project_switcher, false)
      |> assign(:switcher_selected, 0)
      |> assign(:switcher_query, "")
      |> assign(:add_project_error, nil)
      |> assign(:project_path_suggestions, [])
      |> assign(:editing_setting, nil)
      # New project (bootstrap) modal
      |> assign(:show_new_project, false)
      |> assign(:new_project_error, nil)
      |> assign(:bootstrap_progress, nil)
      # Adopt worktree modal
      |> assign(:show_adopt_worktree, false)
      |> assign(:adopt_worktree_error, nil)
      |> assign(:adopt_disk_worktrees, [])
      # Pane focus
      |> assign(:focused_pane, :tree)
      # Task inline input
      |> assign(:adding_task_to, nil)
      # Worktree creation mode
      |> assign(:worktree_mode, false)
      # Search mode
      |> assign(:search_mode, false)
      |> assign(:search_query, "")
      # Preview help
      |> assign(:show_preview_help, false)
      # Theme (actual value set from client via ThemePersist hook)
      |> assign(:theme, "studio")
      # Load state (will be refined in handle_params)
      |> load_dashboard_state(nil)

    {:ok, socket}
  end

  @impl true
  def handle_params(%{"project_id" => project_id, "id" => id}, _uri, socket) do
    socket = apply_project_scope(socket, project_id)
    {:noreply, select_task(socket, id)}
  end

  def handle_params(%{"project_id" => project_id} = params, _uri, socket) do
    socket = apply_project_scope(socket, project_id)
    {:noreply, select_task(socket, params["task"])}
  end

  def handle_params(%{"id" => id}, _uri, socket) do
    socket = apply_project_scope(socket, nil)
    {:noreply, select_task(socket, id)}
  end

  def handle_params(%{"task" => id}, _uri, socket) do
    # Don't reset project scope — task selection is within current view
    {:noreply, select_task(socket, id)}
  end

  def handle_params(_params, _uri, socket) do
    socket = apply_project_scope(socket, nil)
    {:noreply, select_task(socket, nil)}
  end

  defp apply_project_scope(socket, project_id) do
    current = socket.assigns.current_project

    cond do
      is_nil(project_id) && is_nil(current) ->
        socket
        |> apply_swarm_state(nil)
        |> load_dashboard_state(nil)

      is_nil(project_id) && not is_nil(current) ->
        socket
        |> assign(:current_project, nil)
        |> assign(:has_project_preview_config, false)
        |> apply_swarm_state(nil)
        |> load_dashboard_state(nil)

      not is_nil(project_id) && (is_nil(current) || current.id != project_id) ->
        case Projects.get(project_id) do
          {:ok, project} ->
            socket
            |> assign(:current_project, project)
            |> assign(:has_project_preview_config, DevServer.has_config_for_path?(project.path))
            |> apply_swarm_state(project)
            |> load_dashboard_state(project)

          {:error, _} ->
            socket
            |> put_flash(:error, "Project not found")
            |> push_navigate(to: ~p"/")
        end

      true ->
        socket
    end
  end

  defp apply_swarm_state(socket, nil) do
    socket
    |> assign(:swarm_status, :paused)
    |> assign(:target_count, 1)
    |> assign(:active_count, 0)
  end

  defp apply_swarm_state(socket, project) do
    project_status = Dispatcher.project_status(project.id)

    socket
    |> assign(:swarm_status, project_status.status)
    |> assign(:target_count, max(project_status.target_count, 1))
    |> assign(:active_count, project_status.active_count)
  end

  defp load_dashboard_state(socket, project) do
    task_state =
      if project do
        Worktrees.get_state(project_id: project.id)
      else
        Worktrees.get_state()
      end

    agents = socket.assigns[:agents] || []
    dev_servers = socket.assigns[:dev_servers] || %{}
    active_task_ids = active_task_ids_from_agents(agents)

    # Separate questions from task worktrees
    {questions, task_items} =
      Enum.split_with(task_state.tasks, fn item ->
        String.starts_with?(to_string(item.id), "wt-") and
          Map.get(item, :kind) == "question"
      end)

    worktrees_by_status = build_worktree_groups(task_items, agents, dev_servers)

    socket
    |> assign(:stats, task_state.stats)
    |> assign(:ready_tasks, task_state.ready_tasks)
    |> assign(:last_poll, task_state.last_poll)
    |> assign(:error, task_state.error)
    |> assign(:task_count, length(task_state.tasks))
    |> assign(:orphan_count, compute_orphan_count(task_state.tasks, active_task_ids))
    |> assign(:worktrees_by_status, worktrees_by_status)
    |> assign(
      :card_ids,
      build_card_ids(
        worktrees_by_status,
        socket.assigns[:collapsed_done] != false,
        socket.assigns[:collapsed_discarded] != false
      )
    )
    |> assign(:known_task_ids, extract_task_ids(task_state.tasks))
    |> assign(:project_files, load_project_files(project))
    |> assign(:questions, questions)
  end

  # --- PubSub handlers ---

  @impl true
  def handle_info({:worktrees_update, state}, socket) do
    # Re-filter state if scoped to a project
    state = filter_state_for_project(state, socket.assigns.current_project)

    new_ids = extract_task_ids(state.tasks)
    old_ids = socket.assigns.known_task_ids
    created = MapSet.difference(new_ids, old_ids)

    socket =
      if MapSet.size(created) > 0 do
        new_tasks = Enum.filter(state.tasks, &MapSet.member?(created, &1.id))
        names = Enum.map_join(new_tasks, ", ", & &1.title)
        put_flash(socket, :info, "Task added: #{names}")
      else
        socket
      end

    agents = socket.assigns.agents
    active_task_ids = active_task_ids_from_agents(agents)

    {questions, task_items} =
      Enum.split_with(state.tasks, fn item ->
        String.starts_with?(to_string(item.id), "wt-") and
          Map.get(item, :kind) == "question"
      end)

    worktrees_by_status = build_worktree_groups(task_items, agents, socket.assigns.dev_servers)

    socket =
      socket
      |> assign(:stats, state.stats)
      |> assign(:ready_tasks, state.ready_tasks)
      |> assign(:last_poll, state.last_poll)
      |> assign(:error, state.error)
      |> assign(:task_count, length(state.tasks))
      |> assign(:orphan_count, compute_orphan_count(state.tasks, active_task_ids))
      |> assign(:worktrees_by_status, worktrees_by_status)
      |> assign(:known_task_ids, new_ids)
      |> assign(:questions, questions)
      |> rebuild_card_ids(worktrees_by_status)

    socket =
      if socket.assigns.selected_task_id do
        refresh_selected_task(socket)
      else
        socket
      end

    {:noreply, socket}
  end

  @impl true
  def handle_info({:dispatcher_update, status}, socket) do
    old_agents = socket.assigns.agents
    agents = enrich_agents_with_pids(status.agents)

    update_agent_subscriptions(old_agents, agents)

    # Rebuild card groups since agent assignments affect which lane cards appear in
    task_state = scoped_get_state(socket)
    dev_servers = socket.assigns.dev_servers

    {questions, task_items} =
      Enum.split_with(task_state.tasks, fn item ->
        String.starts_with?(to_string(item.id), "wt-") and
          Map.get(item, :kind) == "question"
      end)

    worktrees_by_status = build_worktree_groups(task_items, agents, dev_servers)

    # Extract per-project swarm state for the currently selected project
    project_status = current_project_swarm_status(socket, status)

    socket =
      socket
      |> assign(:swarm_status, project_status.status)
      |> assign(:target_count, max(project_status.target_count, 1))
      |> assign(:active_count, project_status.active_count)
      |> assign(:agents, agents)
      |> assign(:dispatcher_projects, status[:projects] || %{})
      |> assign(:worktrees_by_status, worktrees_by_status)
      |> assign(:questions, questions)
      |> rebuild_card_ids(worktrees_by_status)

    socket =
      if socket.assigns.selected_task_id do
        find_working_agent(socket)
      else
        socket
      end

    {:noreply, socket}
  end

  @impl true
  def handle_info({:dev_server_update, info}, socket) do
    dev_servers = Map.put(socket.assigns.dev_servers, info.worktree_id, info)

    dev_servers =
      if info.status == :stopped do
        Map.delete(dev_servers, info.worktree_id)
      else
        dev_servers
      end

    # Rebuild groups with updated dev server info
    task_state = scoped_get_state(socket)
    agents = socket.assigns.agents
    worktrees_by_status = build_worktree_groups(task_state.tasks, agents, dev_servers)

    socket =
      socket
      |> assign(:dev_servers, dev_servers)
      |> assign(:worktrees_by_status, worktrees_by_status)
      |> rebuild_card_ids(worktrees_by_status)

    # Auto-open preview with logs when a dev server enters error state
    socket =
      if info.status == :error do
        error_port =
          case info[:ports] do
            [%{port: p} | _] -> p
            _ -> 0
          end

        socket
        |> assign(:show_preview, true)
        |> assign(:preview_port, error_port)
        |> assign(:show_preview_logs, true)
      else
        socket
      end

    {:noreply, socket}
  end

  @impl true
  def handle_info({event, _project}, socket)
      when event in [:project_added, :project_updated, :project_deleted] do
    projects = Projects.list_active()
    {:noreply, assign(socket, :projects, projects)}
  end

  @impl true
  def handle_info({:agent_output, agent_id, lines}, socket) do
    working_agent = socket.assigns[:working_agent]

    cond do
      # Already matched — append output
      working_agent && working_agent.id == agent_id ->
        output =
          (socket.assigns.agent_output ++ lines)
          |> Enum.take(-200)

        {:noreply, assign(socket, :agent_output, output)}

      # Not matched yet — try to match this agent to the selected worktree
      is_nil(working_agent) && socket.assigns[:selected_task_id] ->
        agent =
          socket.assigns.agents
          |> Enum.find(fn a ->
            a.id == agent_id &&
              a.current_worktree &&
              to_string(a.current_worktree.id) == to_string(socket.assigns.selected_task_id)
          end)

        if agent do
          output = (socket.assigns.agent_output ++ lines) |> Enum.take(-200)

          {:noreply,
           socket
           |> assign(:working_agent, agent)
           |> assign(:agent_output, output)}
        else
          {:noreply, socket}
        end

      true ->
        {:noreply, socket}
    end
  end

  @impl true
  def handle_info({:agent_state, _agent}, socket) do
    {:noreply, socket}
  end

  @impl true
  def handle_info({:diff_result, worktree_id, {:ok, raw_diff}}, socket) do
    files = DiffParser.parse(raw_diff)

    diff_view =
      if files == [] do
        %{
          files: [],
          selected_file: 0,
          worktree_id: worktree_id,
          loading: false,
          error: "No changes found"
        }
      else
        %{files: files, selected_file: 0, worktree_id: worktree_id, loading: false, error: nil}
      end

    {:noreply, assign(socket, :diff_view, diff_view)}
  end

  @impl true
  def handle_info({:diff_result, worktree_id, {:error, reason}}, socket) do
    diff_view = %{
      files: [],
      selected_file: 0,
      worktree_id: worktree_id,
      loading: false,
      error: "Failed to fetch diff: #{inspect(reason)}"
    }

    {:noreply, assign(socket, :diff_view, diff_view)}
  end

  # Recipe PubSub handlers — refresh the recipe list on any change
  @impl true
  def handle_info({recipe_event, _recipe}, socket)
      when recipe_event in [:recipe_created, :recipe_updated, :recipe_toggled, :recipe_deleted] do
    {:noreply, assign(socket, :recipes, Worktrees.list_recipes())}
  end

  # Bootstrap PubSub handlers
  @impl true
  def handle_info({:bootstrap_progress, _name, message}, socket) do
    {:noreply, assign(socket, :bootstrap_progress, message)}
  end

  @impl true
  def handle_info({:bootstrap_complete, _name, {:ok, project}}, socket) do
    projects = Projects.list_active()

    # Auto-start dev server for the new project
    if DevServer.has_config_for_path?(project.path) do
      DevServer.start_project_server(project.id, project.path)
    end

    {:noreply,
     socket
     |> assign(
       projects: projects,
       show_new_project: false,
       bootstrap_progress: nil,
       new_project_error: nil
     )
     |> put_flash(:info, "Project created: #{project.name}")
     |> push_navigate(to: ~p"/projects/#{project.id}")}
  end

  @impl true
  def handle_info({:bootstrap_complete, _name, {:error, reason}}, socket) do
    {:noreply,
     assign(socket,
       bootstrap_progress: nil,
       new_project_error: "Bootstrap failed: #{inspect(reason)}"
     )}
  end

  # Catch-all for async task results (e.g. Task.async replies) to prevent crashes
  @impl true
  def handle_info({:async_action_result, {:ok, message}}, socket) do
    was_merge = socket.assigns.loading_action in [:merging, :direct_merging, :local_merging]

    socket =
      socket
      |> assign(:loading_action, nil)
      |> put_flash(:info, message)

    # Deselect worktree after merge so new input creates a fresh worktree
    socket =
      if was_merge do
        socket
        |> assign(:selected_task_id, nil)
        |> assign(:selected_task, nil)
      else
        socket
      end

    {:noreply, socket}
  end

  @impl true
  def handle_info({:async_action_result, {:error, message}}, socket) do
    {:noreply,
     socket
     |> assign(:loading_action, nil)
     |> put_flash(:error, message)}
  end

  @impl true
  def handle_info({ref, _result}, socket) when is_reference(ref) do
    Process.demonitor(ref, [:flush])
    {:noreply, socket}
  end

  @impl true
  def handle_info({:DOWN, _ref, :process, _pid, _reason}, socket) do
    {:noreply, socket}
  end

  # --- Event handlers ---

  @impl true
  def handle_event("input-focus", _params, socket),
    do: {:noreply, assign(socket, :input_focused, true)}

  @impl true
  def handle_event("input-blur", _params, socket),
    do: {:noreply, assign(socket, :input_focused, false)}

  @impl true
  def handle_event("switch-to-task-mode", _params, socket) do
    wt_id = socket.assigns.selected_task_id

    if wt_id do
      {:noreply, assign(socket, :adding_task_to, wt_id)}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_event("file-search", %{"query" => query}, socket) do
    results = FileTree.search(query, socket.assigns.project_files)
    {:reply, %{files: results}, socket}
  end

  @impl true
  # Cmd+K (macOS) toggles project switcher
  def handle_event("hotkey", %{"metaKey" => true, "key" => "k"}, socket) do
    cond do
      socket.assigns.show_project_switcher ->
        {:noreply, assign(socket, :show_project_switcher, false)}

      socket.assigns.current_project ->
        {:noreply,
         socket
         |> assign(:show_project_switcher, true)
         |> assign(:switcher_selected, 0)
         |> assign(:switcher_query, "")
         |> push_event("focus-element", %{selector: "#project-switcher-search"})}

      true ->
        {:noreply, socket}
    end
  end

  def handle_event("hotkey", %{"metaKey" => true}, socket), do: {:noreply, socket}

  def handle_event("hotkey", %{"ctrlKey" => true, "key" => key}, socket)
      when key in ["n", "p"] do
    if socket.assigns.show_project_switcher do
      mapped = if key == "n", do: "j", else: "k"
      {:noreply, handle_switcher_hotkey(mapped, socket)}
    else
      {:noreply, socket}
    end
  end

  # Ctrl+H/J/K/L — section navigation (works even when input has focus)
  # Ctrl+H/L = switch panels (tree ↔ detail)
  # Ctrl+J/K = cycle sections (tree → detail → input → tree)
  def handle_event("hotkey", %{"ctrlKey" => true, "key" => key}, socket)
      when key in ["h", "j", "k", "l"] do
    cond do
      socket.assigns.loading_action != nil ->
        {:noreply, socket}

      socket.assigns.show_project_switcher and key in ["j", "k"] ->
        {:noreply, handle_switcher_hotkey(key, socket)}

      socket.assigns.diff_view != nil ->
        {:noreply, handle_diff_hotkey(key, socket)}

      key == "h" ->
        {:noreply,
         socket
         |> assign(:focused_pane, :tree)
         |> assign(:input_focused, false)
         |> push_event("blur-input", %{})}

      key == "l" ->
        {:noreply,
         socket
         |> assign(:focused_pane, :detail)
         |> assign(:input_focused, false)
         |> push_event("blur-input", %{})}

      key == "j" ->
        # Cycle forward: tree → detail → input → tree
        socket =
          cond do
            socket.assigns.input_focused ->
              socket
              |> assign(:input_focused, false)
              |> assign(:focused_pane, :tree)
              |> push_event("blur-input", %{})

            socket.assigns.focused_pane == :tree ->
              assign(socket, :focused_pane, :detail)

            socket.assigns.focused_pane == :detail ->
              socket
              |> assign(:input_focused, true)
              |> push_event("focus-primary-input", %{})

            true ->
              assign(socket, :focused_pane, :tree)
          end

        {:noreply, socket}

      key == "k" ->
        # Cycle backward: input → detail → tree → input
        socket =
          cond do
            socket.assigns.input_focused ->
              socket
              |> assign(:input_focused, false)
              |> assign(:focused_pane, :detail)
              |> push_event("blur-input", %{})

            socket.assigns.focused_pane == :detail ->
              assign(socket, :focused_pane, :tree)

            true ->
              socket
              |> assign(:input_focused, true)
              |> push_event("focus-primary-input", %{})
          end

        {:noreply, socket}
    end
  end

  def handle_event("hotkey", %{"ctrlKey" => true}, socket), do: {:noreply, socket}

  def handle_event("hotkey", %{"key" => key}, socket) do
    cond do
      socket.assigns.show_project_switcher and
          key in ["j", "k", "Tab", "Enter", "Escape", "ArrowDown", "ArrowUp"] ->
        {:noreply, handle_switcher_hotkey(key, socket)}

      socket.assigns.input_focused and key not in ["Escape"] ->
        {:noreply, socket}

      socket.assigns.loading_action != nil ->
        {:noreply, socket}

      socket.assigns.diff_view != nil ->
        {:noreply, handle_diff_hotkey(key, socket)}

      socket.assigns.pending_action != nil ->
        {:noreply, handle_pending_action(key, socket)}

      true ->
        {:noreply, handle_hotkey(key, socket)}
    end
  end

  @impl true
  def handle_event("hotkey", _params, socket), do: {:noreply, socket}

  @impl true
  def handle_event("close-help", _params, socket),
    do: {:noreply, assign(socket, :show_help, false)}

  @impl true
  def handle_event("toggle-help", _params, socket),
    do: {:noreply, assign(socket, :show_help, !socket.assigns.show_help)}

  @impl true
  def handle_event("refresh", _params, socket) do
    Worktrees.force_refresh()
    {:noreply, socket}
  end

  @impl true
  def handle_event("pull-main", _params, socket) do
    case socket.assigns.current_project do
      nil ->
        {:noreply, put_flash(socket, :error, "Select a project first")}

      project ->
        lv = self()

        Elixir.Task.start(fn ->
          result =
            case Git.pull_main(project.path) do
              {:ok, output} ->
                {:ok, "Pulled origin main: #{String.trim(output)}"}

              {:error, reason} ->
                {:error, "Pull failed: #{inspect(reason)}"}
            end

          send(lv, {:async_action_result, result})
        end)

        {:noreply,
         socket
         |> assign(:loading_action, :pulling_main)
         |> put_flash(:info, "Pulling origin main...")}
    end
  end

  @impl true
  def handle_event("start-swarm", _params, socket) do
    case socket.assigns.current_project do
      nil ->
        {:noreply, put_flash(socket, :error, "Select a project first")}

      project ->
        Dispatcher.start_swarm(project.id, socket.assigns.target_count)

        {:noreply,
         put_flash(
           socket,
           :info,
           "Brewing started with #{socket.assigns.target_count} brewers"
         )}
    end
  end

  @impl true
  def handle_event("stop-swarm", _params, socket) do
    case socket.assigns.current_project do
      nil ->
        {:noreply, put_flash(socket, :error, "Select a project first")}

      project ->
        Dispatcher.stop_swarm(project.id)
        {:noreply, put_flash(socket, :info, "Brewing stopped")}
    end
  end

  @impl true
  def handle_event("inc-agents", _params, socket) do
    count = min(socket.assigns.target_count + 1, 10)

    case socket.assigns.current_project do
      nil ->
        {:noreply, put_flash(socket, :error, "Select a project first")}

      project ->
        if socket.assigns.swarm_status == :running do
          Dispatcher.set_agent_count(project.id, count)
        end

        socket = assign(socket, :target_count, count)

        socket =
          if socket.assigns.swarm_status != :running do
            put_flash(socket, :info, "Brewer count set to #{count}")
          else
            socket
          end

        {:noreply, socket}
    end
  end

  @impl true
  def handle_event("dec-agents", _params, socket) do
    count = max(socket.assigns.target_count - 1, 1)

    case socket.assigns.current_project do
      nil ->
        {:noreply, put_flash(socket, :error, "Select a project first")}

      project ->
        if socket.assigns.swarm_status == :running do
          Dispatcher.set_agent_count(project.id, count)
        end

        socket = assign(socket, :target_count, count)

        socket =
          if socket.assigns.swarm_status != :running do
            put_flash(socket, :info, "Brewer count set to #{count}")
          else
            socket
          end

        {:noreply, socket}
    end
  end

  @impl true
  def handle_event("toggle-auto-pr", _params, socket) do
    new_val = !socket.assigns.auto_pr
    Git.set_auto_pr(new_val)

    {:noreply, assign(socket, :auto_pr, new_val)}
  end

  @impl true
  def handle_event("toggle-preview-help", _params, socket) do
    {:noreply, assign(socket, :show_preview_help, !socket.assigns.show_preview_help)}
  end

  @impl true
  def handle_event("show-preview", params, socket) do
    port =
      case params do
        %{"port" => p} when is_binary(p) -> String.to_integer(p)
        %{"port" => p} when is_integer(p) -> p
        _ -> nil
      end

    # Auto-show logs if the server is in error state
    show_logs =
      Enum.any?(socket.assigns.dev_servers, fn {_id, server} ->
        server[:status] == :error and
          Enum.any?(server[:ports] || [], fn p -> p.port == port end)
      end)

    {:noreply,
     socket
     |> assign(:show_preview, true)
     |> assign(:preview_port, port)
     |> assign(:show_preview_logs, show_logs || socket.assigns.show_preview_logs)}
  end

  @impl true
  def handle_event("show-preview-picker", _params, socket) do
    {:noreply, socket |> assign(:show_preview, true) |> assign(:preview_port, nil)}
  end

  @impl true
  def handle_event("close-preview", _params, socket) do
    {:noreply,
     socket
     |> assign(:show_preview, false)
     |> assign(:preview_port, nil)
     |> assign(:show_preview_logs, false)}
  end

  @impl true
  def handle_event("toggle-preview-logs", _params, socket) do
    {:noreply, assign(socket, :show_preview_logs, !socket.assigns.show_preview_logs)}
  end

  @impl true
  def handle_event("toggle-done-collapse", _params, socket) do
    new_collapsed = !socket.assigns.collapsed_done

    socket =
      socket
      |> assign(:collapsed_done, new_collapsed)
      |> then(fn s ->
        new_card_ids =
          build_card_ids(
            s.assigns.worktrees_by_status,
            new_collapsed,
            s.assigns[:collapsed_discarded] != false
          )

        # Preserve selected card position
        old_id = Enum.at(s.assigns.card_ids, s.assigns.selected_card)

        idx =
          if old_id do
            Enum.find_index(new_card_ids, &(&1 == old_id)) ||
              min(s.assigns.selected_card, max(length(new_card_ids) - 1, 0))
          else
            min(s.assigns.selected_card, max(length(new_card_ids) - 1, 0))
          end

        s
        |> assign(:card_ids, new_card_ids)
        |> assign(:selected_card, idx)
      end)

    {:noreply, socket}
  end

  @impl true
  def handle_event("toggle-discarded-collapse", _params, socket) do
    new_collapsed = !socket.assigns.collapsed_discarded

    socket =
      socket
      |> assign(:collapsed_discarded, new_collapsed)
      |> then(fn s ->
        new_card_ids =
          build_card_ids(
            s.assigns.worktrees_by_status,
            s.assigns.collapsed_done,
            new_collapsed
          )

        old_id = Enum.at(s.assigns.card_ids, s.assigns.selected_card)

        idx =
          if old_id do
            Enum.find_index(new_card_ids, &(&1 == old_id)) ||
              min(s.assigns.selected_card, max(length(new_card_ids) - 1, 0))
          else
            min(s.assigns.selected_card, max(length(new_card_ids) - 1, 0))
          end

        s
        |> assign(:card_ids, new_card_ids)
        |> assign(:selected_card, idx)
      end)

    {:noreply, socket}
  end

  @impl true
  def handle_event("focus-tree-pane", _params, socket) do
    {:noreply, assign(socket, :focused_pane, :tree)}
  end

  @impl true
  def handle_event("focus-detail-pane", _params, socket) do
    {:noreply, assign(socket, :focused_pane, :detail)}
  end

  @impl true
  def handle_event("select-task", %{"id" => id}, socket) do
    {:noreply, push_patch(socket, to: project_path(socket) <> "?task=#{id}")}
  end

  @impl true
  def handle_event("deselect-task", _params, socket) do
    {:noreply, push_patch(socket, to: project_path(socket))}
  end

  @impl true
  def handle_event("add-task-to-worktree", %{"id" => wt_id}, socket) do
    {:noreply,
     socket
     |> assign(:adding_task_to, wt_id)
     |> push_event("focus-element", %{selector: "#primary-input"})}
  end

  # Legacy inline task creation (now handled by submit-input in task-add mode)
  @impl true
  def handle_event("add-task-inline", %{"title" => title, "worktree_id" => wt_id}, socket) do
    title = String.trim(title)

    if title != "" do
      Worktrees.create_task(%{title: title, worktree_id: wt_id, priority: 3})
    end

    {:noreply, assign(socket, :adding_task_to, nil)}
  end

  # Search tree
  @impl true
  def handle_event("search-tree", %{"query" => query}, socket) do
    {:noreply, assign(socket, :search_query, query)}
  end

  @impl true
  def handle_event("search-select", %{"query" => query}, socket) do
    query = String.trim(query)

    if query == "" do
      {:noreply,
       socket
       |> assign(:search_query, "")
       |> assign(:input_focused, false)
       |> push_event("blur-input", %{})}
    else
      query_lower = String.downcase(query)

      # Try to find a matching worktree first
      match_idx =
        Enum.find_index(socket.assigns.card_ids, fn card_id ->
          entry = find_entry_by_id(socket.assigns.worktrees_by_status, card_id)

          entry &&
            String.contains?(
              String.downcase(entry.worktree.title || entry.worktree.id),
              query_lower
            )
        end)

      if match_idx do
        # Found a match — select it
        {:noreply,
         socket
         |> assign(:search_query, "")
         |> assign(:selected_card, match_idx)
         |> assign(:input_focused, false)
         |> push_event("blur-input", %{})}
      else
        # No match — just clear the search
        {:noreply,
         socket
         |> assign(:search_query, "")
         |> assign(:input_focused, false)
         |> push_event("blur-input", %{})
         |> put_flash(:info, "No match. Press 'b' to create a worktree.")}
      end
    end
  end

  @impl true
  def handle_event("search-blur", _params, socket) do
    {:noreply,
     socket
     |> assign(:search_query, "")
     |> assign(:input_focused, false)}
  end

  @impl true
  def handle_event("requeue-orphans", _params, socket) do
    active_ids = active_task_ids_from_agents(socket.assigns.agents)

    {:ok, count} = Worktrees.requeue_all_orphans(active_ids)
    {:noreply, put_flash(socket, :info, "Requeued #{count} orphaned task(s)")}
  end

  # Preview controls

  # Start dev server for selected worktree and open preview panel
  @impl true
  def handle_event("preview-worktree", _params, socket) do
    wt_id = socket.assigns.selected_task_id

    if wt_id do
      case DevServer.start_server(wt_id) do
        {:ok, base_port} ->
          {:noreply,
           socket
           |> assign(:show_preview, true)
           |> assign(:preview_port, base_port)
           |> assign(:has_preview_config, true)}

        {:error, :already_running} ->
          # Already running — just open the preview with its port
          port =
            case DevServer.get_status(wt_id) do
              %{ports: [%{port: p} | _]} -> p
              _ -> nil
            end

          {:noreply,
           socket
           |> assign(:show_preview, true)
           |> assign(:preview_port, port)}

        {:error, :no_dev_config} ->
          {:noreply, put_flash(socket, :error, "No .apothecary/preview.yml found in worktree")}

        {:error, reason} ->
          {:noreply, put_flash(socket, :error, "Failed to start preview: #{inspect(reason)}")}
      end
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_event("start-dev", %{"id" => wt_id}, socket) do
    # Re-check config existence (file may have been added since selection)
    has_config =
      try do
        DevServer.has_config?(wt_id)
      catch
        :exit, _ -> false
      end

    socket = assign(socket, :has_preview_config, has_config)

    case DevServer.start_server(wt_id) do
      {:ok, _base_port} ->
        {:noreply, put_flash(socket, :info, "Preview starting for #{wt_id}")}

      {:error, :no_dev_config} ->
        {:noreply, put_flash(socket, :error, "No .apothecary/preview.yml found in worktree")}

      {:error, :already_running} ->
        {:noreply, put_flash(socket, :info, "Preview already running")}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Failed to start preview: #{inspect(reason)}")}
    end
  end

  @impl true
  def handle_event("stop-dev", %{"id" => wt_id}, socket) do
    DevServer.stop_server(wt_id)
    {:noreply, put_flash(socket, :info, "Preview stopped for #{wt_id}")}
  end

  @impl true
  def handle_event("restart-preview", %{"id" => server_id}, socket) do
    DevServer.stop_server(server_id)

    project = socket.assigns.current_project

    result =
      if project && server_id == project.id do
        DevServer.start_project_server(project.id, project.path)
      else
        DevServer.start_server(server_id)
      end

    case result do
      {:ok, _} ->
        {:noreply, put_flash(socket, :info, "Restarting preview...")}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Restart failed: #{inspect(reason)}")}
    end
  end

  # Project-level dev server controls
  @impl true
  def handle_event("start-project-dev", _params, socket) do
    project = socket.assigns.current_project

    if project do
      # Re-check config existence (file may have been added since page load)
      socket =
        assign(socket, :has_project_preview_config, DevServer.has_config_for_path?(project.path))

      case DevServer.start_project_server(project.id, project.path) do
        {:ok, _base_port} ->
          {:noreply, put_flash(socket, :info, "Starting dev server for #{project.name}")}

        {:error, :no_dev_config} ->
          {:noreply,
           put_flash(socket, :error, "Could not detect dev server config for this project")}

        {:error, :already_running} ->
          {:noreply, put_flash(socket, :info, "Dev server already running")}

        {:error, reason} ->
          {:noreply, put_flash(socket, :error, "Failed to start: #{inspect(reason)}")}
      end
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_event("stop-project-dev", _params, socket) do
    project = socket.assigns.current_project

    if project do
      DevServer.stop_server(project.id)
      {:noreply, put_flash(socket, :info, "Dev server stopped")}
    else
      {:noreply, socket}
    end
  end

  # Card inline task creation
  @impl true
  def handle_event("create-card-task", %{"worktree_id" => wt_id, "title" => title}, socket) do
    title = String.trim(title)

    if title != "" do
      case Worktrees.create_task(%{title: title, worktree_id: wt_id, priority: 3}) do
        {:ok, item} when not is_nil(item) ->
          {:noreply, put_flash(socket, :info, "Task added: #{item.id}")}

        _ ->
          {:noreply, put_flash(socket, :error, "Failed to add task")}
      end
    else
      {:noreply, socket}
    end
  end

  # --- Task detail events ---

  @impl true
  def handle_event("claim", _params, socket) do
    case Worktrees.claim(socket.assigns.selected_task_id) do
      {:ok, _} ->
        {:noreply, put_flash(socket, :info, "Task claimed")}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Failed to claim: #{inspect(reason)}")}
    end
  end

  @impl true
  def handle_event("close-task", _params, socket) do
    case Worktrees.close(socket.assigns.selected_task_id) do
      {:ok, _} ->
        {:noreply, put_flash(socket, :info, "Task closed")}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Failed to close: #{inspect(reason)}")}
    end
  end

  @impl true
  def handle_event("show-diff", _params, socket) do
    case selected_worktree(socket) do
      nil -> {:noreply, socket}
      wt -> {:noreply, start_diff_fetch(socket, wt)}
    end
  end

  @impl true
  def handle_event("merge-pr", _params, %{assigns: %{loading_action: la}} = socket)
      when la != nil,
      do: {:noreply, socket}

  def handle_event("merge-pr", _params, socket) do
    task = socket.assigns.selected_task
    pr_url = task && Map.get(task, :pr_url)

    cond do
      is_nil(pr_url) ->
        {:noreply, put_flash(socket, :error, "No PR URL on this worktree")}

      task.status != "pr_open" ->
        {:noreply, put_flash(socket, :error, "Worktree is not in pr_open status")}

      true ->
        {:noreply, assign(socket, :pending_action, {:merge, task.id, pr_url})}
    end
  end

  @impl true
  def handle_event("confirm-merge", _params, %{assigns: %{loading_action: la}} = socket)
      when la != nil,
      do: {:noreply, socket}

  def handle_event("confirm-merge", _params, socket) do
    case socket.assigns.pending_action do
      {:merge, task_id, pr_url} ->
        socket = assign(socket, :pending_action, nil)
        {:noreply, execute_merge(socket, task_id, pr_url)}

      {:direct_merge, task_id, git_path} ->
        socket = assign(socket, :pending_action, nil)
        {:noreply, execute_direct_merge(socket, task_id, git_path)}

      {:local_merge, task_id, git_path} ->
        socket = assign(socket, :pending_action, nil)
        {:noreply, execute_local_merge(socket, task_id, git_path)}

      _ ->
        {:noreply, assign(socket, :pending_action, nil)}
    end
  end

  @impl true
  def handle_event("cancel-merge", _params, socket) do
    {:noreply, assign(socket, :pending_action, nil)}
  end

  @impl true
  def handle_event("direct-merge", _params, %{assigns: %{loading_action: la}} = socket)
      when la != nil,
      do: {:noreply, socket}

  def handle_event("direct-merge", _params, socket) do
    task = socket.assigns.selected_task

    cond do
      is_nil(task) || task.status != "brew_done" ->
        {:noreply, put_flash(socket, :error, "Worktree is not ready for merge")}

      is_nil(task.git_path) ->
        {:noreply, put_flash(socket, :error, "No git path found for this worktree")}

      true ->
        {:noreply, assign(socket, :pending_action, {:direct_merge, task.id, task.git_path})}
    end
  end

  @impl true
  def handle_event("local-merge", _params, %{assigns: %{loading_action: la}} = socket)
      when la != nil,
      do: {:noreply, socket}

  def handle_event("local-merge", _params, socket) do
    task = socket.assigns.selected_task

    cond do
      is_nil(task) || task.status not in ["brew_done", "done", "closed"] ->
        {:noreply, put_flash(socket, :error, "Worktree is not ready for merge")}

      is_nil(task.git_path) ->
        {:noreply, put_flash(socket, :error, "No git path found for this worktree")}

      true ->
        {:noreply, assign(socket, :pending_action, {:local_merge, task.id, task.git_path})}
    end
  end

  @impl true
  def handle_event("promote-to-assaying", _params, %{assigns: %{loading_action: la}} = socket)
      when la != nil,
      do: {:noreply, socket}

  def handle_event("promote-to-assaying", _params, socket) do
    task = socket.assigns.selected_task

    cond do
      is_nil(task) || task.status != "brew_done" ->
        {:noreply, put_flash(socket, :error, "Worktree is not ready for promotion")}

      true ->
        {:noreply, promote_to_assaying(socket, task)}
    end
  end

  @impl true
  def handle_event("requeue", _params, socket) do
    case Worktrees.unclaim(socket.assigns.selected_task_id) do
      {:ok, _} ->
        {:noreply, put_flash(socket, :info, "Task requeued")}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Failed to requeue: #{inspect(reason)}")}
    end
  end

  @impl true
  def handle_event("approve-merge-fix", _params, socket) do
    worktree_id = socket.assigns.selected_task_id

    # Unblock the fix-merge-conflicts task(s) by setting them to "open"
    fix_tasks =
      Worktrees.list_tasks(worktree_id: worktree_id)
      |> Enum.filter(fn t ->
        t.status == "blocked" and String.contains?(t.title || "", "merge conflict")
      end)

    case fix_tasks do
      [] ->
        {:noreply, put_flash(socket, :error, "No merge conflict task found to approve")}

      fix_list ->
        for fix_item <- fix_list do
          Worktrees.update_task(fix_item.id, %{status: "open"})
        end

        # Set worktree back to open so it gets dispatched
        Worktrees.update_worktree(worktree_id, %{status: "open"})

        {:noreply,
         put_flash(socket, :info, "Merge fix approved — worktree will be re-dispatched")}
    end
  end

  @impl true
  def handle_event("change-priority", %{"dir" => dir}, socket) do
    id = socket.assigns.selected_task_id

    if id do
      task = socket.assigns.selected_task
      current = (task && task.priority) || 3

      new_priority =
        case dir do
          "up" -> max(current - 1, 0)
          "down" -> min(current + 1, 4)
        end

      if new_priority != current do
        Worktrees.update_priority(id, new_priority)
      end
    end

    {:noreply, socket}
  end

  @impl true
  def handle_event("start-edit", %{"field" => field}, socket) do
    {:noreply, assign(socket, :editing_field, String.to_existing_atom(field))}
  end

  @impl true
  def handle_event("cancel-edit", _params, socket) do
    {:noreply, assign(socket, :editing_field, nil)}
  end

  @impl true
  def handle_event("save-edit", %{"field" => "title", "value" => value}, socket) do
    value = String.trim(value)

    if value != "" do
      Worktrees.update_title(socket.assigns.selected_task_id, value)
    end

    {:noreply, assign(socket, :editing_field, nil)}
  end

  @impl true
  def handle_event("save-edit", %{"field" => "description", "value" => value}, socket) do
    Worktrees.update_description(socket.assigns.selected_task_id, String.trim(value))
    {:noreply, assign(socket, :editing_field, nil)}
  end

  @impl true
  def handle_event("create-child", %{"title" => title}, socket) do
    title = String.trim(title)

    if title != "" do
      selected = socket.assigns.selected_task_id

      worktree_id =
        if String.starts_with?(to_string(selected), "wt-") do
          selected
        else
          case Worktrees.get_task(selected) do
            {:ok, task} -> task.worktree_id
            _ -> selected
          end
        end

      Worktrees.create_task(%{title: title, worktree_id: worktree_id, priority: 3})
    end

    {:noreply, socket}
  end

  @impl true
  def handle_event("edit-child", %{"id" => id}, socket) do
    {:noreply, assign(socket, :editing_child_id, id)}
  end

  @impl true
  def handle_event("cancel-child-edit", _params, socket) do
    {:noreply, assign(socket, :editing_child_id, nil)}
  end

  @impl true
  def handle_event("save-child-edit", %{"task_id" => id, "title" => title}, socket) do
    title = String.trim(title)

    if title != "" do
      Worktrees.update_task(id, %{title: title})
    end

    {:noreply, assign(socket, :editing_child_id, nil)}
  end

  @impl true
  def handle_event("delete-child", %{"id" => id}, socket) do
    Worktrees.delete_task(id)
    {:noreply, assign(socket, :editing_child_id, nil)}
  end

  @impl true
  def handle_event("toggle-child-status", %{"id" => id}, socket) do
    case Worktrees.get_task(id) do
      {:ok, task} ->
        new_status = if task.status in ["done", "closed"], do: "open", else: "done"
        Worktrees.update_task(id, %{status: new_status})

      _ ->
        :ok
    end

    {:noreply, socket}
  end

  @impl true
  def handle_event("add-dep", %{"dep_id" => dep_id}, socket) do
    dep_id = String.trim(dep_id)

    if dep_id != "" do
      Worktrees.add_dependency(socket.assigns.selected_task_id, dep_id)
    end

    {:noreply, socket}
  end

  @impl true
  def handle_event("remove-dep", %{"blocker_id" => blocker_id}, socket) do
    Worktrees.remove_dependency(socket.assigns.selected_task_id, blocker_id)
    {:noreply, socket}
  end

  @impl true
  def handle_event("add-mcp", %{"mcp_name" => name, "mcp_url" => url}, socket) do
    name = String.trim(name)
    url = String.trim(url)

    if name != "" and url != "" do
      task_id = socket.assigns.selected_task_id

      existing =
        case Worktrees.get_worktree(task_id) do
          {:ok, wt} -> wt.mcp_servers || %{}
          _ -> %{}
        end

      # Detect if url looks like a command (no :// scheme) vs HTTP URL
      server_config =
        if String.contains?(url, "://") do
          %{"type" => "http", "url" => url}
        else
          # Treat as stdio command
          %{"type" => "stdio", "command" => url}
        end

      updated = Map.put(existing, name, server_config)
      Worktrees.update_worktree(task_id, %{mcp_servers: updated})
    end

    {:noreply, socket}
  end

  @impl true
  def handle_event("remove-mcp", %{"name" => name}, socket) do
    task_id = socket.assigns.selected_task_id

    case Worktrees.get_worktree(task_id) do
      {:ok, wt} ->
        updated = Map.delete(wt.mcp_servers || %{}, name)
        mcp_servers = if updated == %{}, do: nil, else: updated
        Worktrees.update_worktree(task_id, %{mcp_servers: mcp_servers})

      _ ->
        :ok
    end

    {:noreply, socket}
  end

  # Handle pasted images from chat input — save to persistent uploads dir
  @impl true
  def handle_event("paste-image-chat", %{"data" => data, "mime" => mime, "name" => name}, socket) do
    case save_uploaded_image(data, mime, name) do
      {:ok, path} ->
        {:noreply, push_event(socket, "chat-image-saved", %{path: path})}

      :error ->
        {:noreply, put_flash(socket, :error, "Failed to decode pasted image")}
    end
  end

  # Handle pasted images — save to persistent uploads dir
  @impl true
  def handle_event("paste-image", %{"data" => data, "mime" => mime, "name" => name}, socket) do
    case save_uploaded_image(data, mime, name) do
      {:ok, path} ->
        {:noreply, push_event(socket, "image-pasted", %{path: path})}

      :error ->
        {:noreply, put_flash(socket, :error, "Failed to decode pasted image")}
    end
  end

  # Handle pasted images in task input — save to persistent uploads dir
  @impl true
  def handle_event(
        "paste-image-task",
        %{"data" => data, "mime" => mime, "name" => name, "worktree_id" => _wt_id},
        socket
      ) do
    case save_uploaded_image(data, mime, name) do
      {:ok, path} ->
        {:noreply, push_event(socket, "task-image-pasted", %{path: path})}

      :error ->
        {:noreply, put_flash(socket, :error, "Failed to decode pasted image")}
    end
  end

  @impl true
  def handle_event("toggle-follow-up", %{"question-id" => qid}, socket) do
    current = socket.assigns.follow_up_question_id

    {:noreply,
     assign(socket, :follow_up_question_id, if(current == qid, do: nil, else: qid))}
  end

  @impl true
  def handle_event("submit-follow-up", %{"follow_up_text" => text, "parent_question_id" => parent_qid}, socket) do
    text = String.trim(text)

    if text == "" do
      {:noreply, socket}
    else
      # Find the parent question to get its parent_worktree_id and project_id
      parent_q =
        Enum.find(socket.assigns.questions, fn q -> q.id == parent_qid end)

      project_id =
        if parent_q, do: parent_q.project_id, else:
          if(socket.assigns.current_project, do: socket.assigns.current_project.id, else: nil)

      parent_worktree_id =
        if parent_q, do: Map.get(parent_q, :parent_worktree_id), else: socket.assigns.selected_task_id

      attrs = %{
        title: text,
        kind: "question",
        priority: 2,
        project_id: project_id,
        parent_question_id: parent_qid
      }

      attrs =
        if parent_worktree_id, do: Map.put(attrs, :parent_worktree_id, parent_worktree_id), else: attrs

      case Worktrees.create_worktree(attrs) do
        {:ok, item} when not is_nil(item) ->
          if project_id do
            Dispatcher.dispatch_question(project_id, item.id)
          end

          {:noreply,
           socket
           |> assign(:follow_up_question_id, nil)
           |> put_flash(:info, "Follow-up question submitted")}

        _ ->
          {:noreply, put_flash(socket, :error, "Failed to submit follow-up")}
      end
    end
  end

  @impl true
  def handle_event("clear-task-input-mode", _params, socket) do
    {:noreply,
     socket
     |> assign(:adding_task_to, nil)
     |> assign(:selected_card, -1)
     |> push_event("focus-element", %{selector: "#primary-input"})}
  end

  # Context-sensitive primary input submit
  @impl true
  def handle_event("submit-input", params, socket) do
    text = String.trim(params["text"] || "")
    images = params["images"] || []

    cond do
      text == "" && images == [] ->
        {:noreply, socket}

      # Worktree creation mode: create worktree with typed name
      socket.assigns.worktree_mode ->
        project_id =
          if socket.assigns.current_project, do: socket.assigns.current_project.id, else: nil

        description = build_description_with_images("", images)

        case Worktrees.create_worktree(%{
               title: text,
               description: description,
               priority: 3,
               project_id: project_id
             }) do
          {:ok, item} when not is_nil(item) ->
            {:noreply,
             socket
             |> assign(:worktree_mode, false)
             |> select_task(item.id)
             |> put_flash(:info, "Worktree created: #{text} — add tasks to start")}

          _ ->
            {:noreply, put_flash(socket, :error, "Failed to create worktree")}
        end

      # Task-add mode: create task in focused worktree (takes priority over ? prefix)
      socket.assigns.adding_task_to ->
        wt_id = socket.assigns.adding_task_to
        description = build_description_with_images("", images)

        case Worktrees.create_task(%{
               title: text,
               description: description,
               worktree_id: wt_id,
               priority: 3
             }) do
          {:ok, item} when not is_nil(item) ->
            {:noreply, put_flash(socket, :info, "Task added: #{item.title}")}

          _ ->
            {:noreply, put_flash(socket, :error, "Failed to add task")}
        end

      # Active agent with + prefix: force task creation
      socket.assigns.working_agent && String.starts_with?(text, "+") ->
        task_text = text |> String.trim_leading("+") |> String.trim()
        wt_id = socket.assigns.selected_task_id
        description = build_description_with_images("", images)

        if task_text != "" && wt_id do
          case Worktrees.create_task(%{
                 title: task_text,
                 description: description,
                 worktree_id: wt_id,
                 priority: 3
               }) do
            {:ok, item} when not is_nil(item) ->
              {:noreply, put_flash(socket, :info, "Task queued: #{item.title}")}

            _ ->
              {:noreply, put_flash(socket, :error, "Failed to queue task")}
          end
        else
          {:noreply, socket}
        end

      # Active agent: send as instruction to brewer
      socket.assigns.working_agent ->
        send_to_agent(text, images, socket)

      # ? prefix asks a question in the focused worktree's context
      String.starts_with?(text, "?") && socket.assigns.selected_task_id ->
        create_question_for_worktree(text, socket)

      # Chat input with a focused worktree: add task
      socket.assigns.selected_task_id ->
        wt_id = socket.assigns.selected_task_id
        description = build_description_with_images("", images)

        case Worktrees.create_task(%{
               title: text,
               description: description,
               worktree_id: wt_id,
               priority: 3
             }) do
          {:ok, item} when not is_nil(item) ->
            {:noreply, put_flash(socket, :info, "Task queued: #{item.title}")}

          _ ->
            {:noreply, put_flash(socket, :error, "Failed to queue task")}
        end

      true ->
        # No context — hint the user to press 'b' or select a worktree
        {:noreply,
         put_flash(
           socket,
           :info,
           "Press 'b' to create a worktree, or select one to add tasks"
         )}
    end
  end

  # --- Tab navigation ---

  @impl true
  def handle_event("switch-tab", %{"tab" => tab}, socket) do
    active_tab = String.to_existing_atom(tab)
    {:noreply, assign(socket, :active_tab, active_tab)}
  end

  @impl true
  def handle_event("set-theme", %{"theme" => theme}, socket)
      when theme in ~w(moonlight studio daylight) do
    {:noreply, assign(socket, :theme, theme)}
  end

  # --- Project event handlers ---

  @impl true
  def handle_event("toggle-project-switcher", _params, socket) do
    opening = !socket.assigns.show_project_switcher

    socket =
      socket
      |> assign(:show_project_switcher, opening)
      |> then(fn s ->
        if opening do
          s
          |> assign(:switcher_selected, 0)
          |> assign(:switcher_query, "")
          |> push_event("focus-element", %{selector: "#project-switcher-search"})
        else
          s
        end
      end)

    {:noreply, socket}
  end

  @impl true
  def handle_event("close-project-switcher", _params, socket) do
    {:noreply, assign(socket, :show_project_switcher, false)}
  end

  @impl true
  def handle_event("switcher-search", %{"query" => query}, socket) do
    {:noreply,
     socket
     |> assign(:switcher_query, query)
     |> assign(:switcher_selected, 0)}
  end

  @impl true
  def handle_event("switcher-hover", %{"index" => index}, socket) do
    {:noreply, assign(socket, :switcher_selected, String.to_integer(index))}
  end

  @impl true
  def handle_event("switcher-select", _params, socket) do
    filtered = filter_projects(socket.assigns.projects, socket.assigns.switcher_query)

    case Enum.at(filtered, socket.assigns.switcher_selected) do
      nil ->
        {:noreply, socket}

      project ->
        {:noreply,
         socket
         |> assign(:show_project_switcher, false)
         |> push_navigate(to: ~p"/projects/#{project.id}")}
    end
  end

  @impl true
  def handle_event("edit-setting", %{"setting" => setting}, socket) do
    {:noreply, assign(socket, :editing_setting, String.to_existing_atom(setting))}
  end

  @impl true
  def handle_event("confirm-setting", _params, socket) do
    {:noreply, assign(socket, :editing_setting, nil)}
  end

  @impl true
  def handle_event("increment-brewers", _params, socket) do
    count = min(socket.assigns.target_count + 1, 8)

    if socket.assigns.current_project && socket.assigns.swarm_status == :running do
      Dispatcher.set_agent_count(socket.assigns.current_project.id, count)
    end

    {:noreply, assign(socket, :target_count, count)}
  end

  @impl true
  def handle_event("decrement-brewers", _params, socket) do
    count = max(socket.assigns.target_count - 1, 1)

    if socket.assigns.current_project && socket.assigns.swarm_status == :running do
      Dispatcher.set_agent_count(socket.assigns.current_project.id, count)
    end

    {:noreply, assign(socket, :target_count, count)}
  end

  @impl true
  def handle_event("search-project-path", %{"path" => path}, socket) do
    suggestions = list_path_suggestions(expand_tilde(path))
    {:noreply, assign(socket, :project_path_suggestions, suggestions)}
  end

  @impl true
  def handle_event("select-project-path", %{"path" => path}, socket) do
    # Append / so the next search shows contents of this directory
    path_with_slash = path <> "/"

    {:noreply,
     socket
     |> assign(project_path_suggestions: list_path_suggestions(path_with_slash))
     |> push_event("set-input-value", %{
       selector: ~s(input[name="path"]),
       value: path_with_slash
     })
     |> push_event("focus-element", %{selector: "#project-path-input"})}
  end

  @impl true
  def handle_event("add-project", %{"path" => path}, socket) do
    path = path |> String.trim() |> expand_tilde()

    if path == "" do
      {:noreply, assign(socket, :add_project_error, "Path cannot be empty")}
    else
      case Projects.validate_path(path) do
        :ok ->
          case Projects.add(path) do
            {:ok, project} ->
              projects = Projects.list_active()

              {:noreply,
               socket
               |> assign(projects: projects, add_project_error: nil)
               |> put_flash(:info, "Project added: #{project.name}")
               |> push_navigate(to: ~p"/projects/#{project.id}")}

            {:error, {:already_exists, existing}} ->
              {:noreply,
               socket
               |> assign(add_project_error: nil)
               |> push_navigate(to: ~p"/projects/#{existing.id}")}

            {:error, reason} ->
              {:noreply, assign(socket, :add_project_error, "Failed: #{inspect(reason)}")}
          end

        {:error, :not_a_directory} ->
          {:noreply, assign(socket, :add_project_error, "Not a valid directory")}

        {:error, :not_a_git_repo} ->
          {:noreply, assign(socket, :add_project_error, "Not a git repository")}
      end
    end
  end

  @impl true
  def handle_event("remove-project", %{"id" => project_id}, socket) do
    case Projects.archive(project_id) do
      {:ok, _} ->
        projects = Projects.list_active()

        socket =
          if socket.assigns.current_project && socket.assigns.current_project.id == project_id do
            socket
            |> assign(current_project: nil, projects: projects)
            |> push_navigate(to: ~p"/")
          else
            assign(socket, :projects, projects)
          end

        {:noreply, put_flash(socket, :info, "Project archived")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to archive project")}
    end
  end

  # --- Bootstrap event handlers ---

  @impl true
  def handle_event("show-new-project", _params, socket) do
    {:noreply,
     assign(socket,
       show_new_project: true,
       new_project_error: nil,
       bootstrap_progress: nil
     )}
  end

  @impl true
  def handle_event("cancel-new-project", _params, socket) do
    {:noreply,
     assign(socket,
       show_new_project: false,
       new_project_error: nil,
       bootstrap_progress: nil
     )}
  end

  @impl true
  def handle_event(
        "create-new-project",
        %{"parent_dir" => parent_dir, "name" => name, "template" => template},
        socket
      ) do
    name = String.trim(name)
    parent_dir = String.trim(parent_dir)
    template = String.to_existing_atom(template)

    cond do
      name == "" ->
        {:noreply, assign(socket, :new_project_error, "Name cannot be empty")}

      parent_dir == "" ->
        {:noreply, assign(socket, :new_project_error, "Parent directory cannot be empty")}

      not File.dir?(Path.expand(parent_dir)) ->
        {:noreply, assign(socket, :new_project_error, "Parent directory does not exist")}

      true ->
        Apothecary.Bootstrapper.subscribe()

        case Apothecary.Bootstrapper.create(parent_dir, name, template) do
          {:ok, _task} ->
            {:noreply,
             assign(socket,
               bootstrap_progress: "Starting...",
               new_project_error: nil
             )}

          {:error, :already_exists} ->
            {:noreply, assign(socket, :new_project_error, "Directory already exists")}

          {:error, msg} when is_binary(msg) ->
            {:noreply, assign(socket, :new_project_error, msg)}

          {:error, reason} ->
            {:noreply, assign(socket, :new_project_error, "Failed: #{inspect(reason)}")}
        end
    end
  end

  # --- Adopt worktree event handlers ---

  @impl true
  def handle_event("show-adopt-worktree", _params, socket) do
    # Scan disk for worktree directories under the current project
    disk_worktrees =
      case socket.assigns.current_project do
        %{path: path} when is_binary(path) ->
          known_ids =
            Worktrees.list_worktrees(project_id: socket.assigns.current_project.id)
            |> MapSet.new(& &1.id)

          WorktreeManager.list_on_disk(path)
          |> Enum.map(fn {id, full_path} ->
            %{id: id, path: full_path, tracked: MapSet.member?(known_ids, id)}
          end)

        _ ->
          []
      end

    {:noreply,
     assign(socket,
       show_adopt_worktree: true,
       adopt_worktree_error: nil,
       adopt_disk_worktrees: disk_worktrees
     )}
  end

  @impl true
  def handle_event("cancel-adopt-worktree", _params, socket) do
    {:noreply,
     assign(socket,
       show_adopt_worktree: false,
       adopt_worktree_error: nil
     )}
  end

  @impl true
  def handle_event("adopt-worktree", %{"path" => path}, socket) do
    path = String.trim(path)

    if path == "" do
      {:noreply, assign(socket, :adopt_worktree_error, "Path cannot be empty")}
    else
      project_id =
        if socket.assigns.current_project, do: socket.assigns.current_project.id, else: nil

      case Worktrees.adopt_worktree(path, project_id: project_id) do
        {:ok, wt} ->
          {:noreply,
           socket
           |> assign(show_adopt_worktree: false, adopt_worktree_error: nil)
           |> select_task(wt.id)
           |> put_flash(:info, "Worktree opened: #{wt.title}")}

        {:error, :not_a_directory} ->
          {:noreply, assign(socket, :adopt_worktree_error, "Path is not a directory")}

        {:error, :not_a_git_repo} ->
          {:noreply, assign(socket, :adopt_worktree_error, "Directory is not a git repository")}

        {:error, reason} ->
          {:noreply,
           assign(socket, :adopt_worktree_error, "Failed to open worktree: #{inspect(reason)}")}
      end
    end
  end

  # --- Recipe event handlers ---

  @impl true
  def handle_event("show-recipe-form", _params, socket) do
    form =
      to_form(%{"title" => "", "description" => "", "schedule" => "", "priority" => "3"},
        as: :recipe
      )

    {:noreply,
     socket
     |> assign(:show_recipe_form, true)
     |> assign(:recipe_form, form)
     |> assign(:editing_recipe_id, nil)}
  end

  @impl true
  def handle_event("cancel-recipe-form", _params, socket) do
    {:noreply,
     socket
     |> assign(:show_recipe_form, false)
     |> assign(:editing_recipe_id, nil)}
  end

  @impl true
  def handle_event("save-recipe", %{"recipe" => params}, socket) do
    attrs = %{
      title: params["title"],
      description: params["description"],
      schedule: params["schedule"],
      priority: parse_priority(params["priority"])
    }

    result =
      if socket.assigns.editing_recipe_id do
        Worktrees.update_recipe(socket.assigns.editing_recipe_id, attrs)
      else
        Worktrees.create_recipe(attrs)
      end

    case result do
      {:ok, _recipe} ->
        {:noreply,
         socket
         |> assign(:show_recipe_form, false)
         |> assign(:editing_recipe_id, nil)
         |> assign(:recipes, Worktrees.list_recipes())
         |> put_flash(
           :info,
           if(socket.assigns.editing_recipe_id, do: "Recipe updated", else: "Recipe created")
         )}

      {:error, {:invalid_schedule, _}} ->
        {:noreply, put_flash(socket, :error, "Invalid cron expression")}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Error: #{inspect(reason)}")}
    end
  end

  @impl true
  def handle_event("toggle-recipe", %{"id" => id}, socket) do
    Worktrees.toggle_recipe(id)
    {:noreply, assign(socket, :recipes, Worktrees.list_recipes())}
  end

  @impl true
  def handle_event("edit-recipe", %{"id" => id}, socket) do
    case Worktrees.get_recipe(id) do
      {:ok, recipe} ->
        form =
          to_form(
            %{
              "title" => recipe.title || "",
              "description" => recipe.description || "",
              "schedule" => recipe.schedule || "",
              "priority" => to_string(recipe.priority || 3)
            },
            as: :recipe
          )

        {:noreply,
         socket
         |> assign(:show_recipe_form, true)
         |> assign(:recipe_form, form)
         |> assign(:editing_recipe_id, id)}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Recipe not found")}
    end
  end

  @impl true
  def handle_event("delete-recipe", %{"id" => id}, socket) do
    Worktrees.delete_recipe(id)
    {:noreply, assign(socket, :recipes, Worktrees.list_recipes())}
  end

  defp parse_priority(nil), do: 3
  defp parse_priority(""), do: 3
  defp parse_priority(s) when is_binary(s), do: String.to_integer(s)
  defp parse_priority(n) when is_integer(n), do: n

  # --- Oracle hotkey handlers ---

  # --- Project switcher hotkeys ---

  defp handle_switcher_hotkey(key, socket) when key in ["j", "Tab", "ArrowDown"] do
    filtered = filter_projects(socket.assigns.projects, socket.assigns.switcher_query)
    # +1 for the "open another project" item at the bottom
    max_idx = length(filtered)

    socket
    |> assign(:switcher_selected, min(socket.assigns.switcher_selected + 1, max_idx))
    |> push_event("scroll-to-selected", %{})
  end

  defp handle_switcher_hotkey(key, socket) when key in ["k", "ArrowUp"] do
    socket
    |> assign(:switcher_selected, max(socket.assigns.switcher_selected - 1, 0))
    |> push_event("scroll-to-selected", %{})
  end

  defp handle_switcher_hotkey("Enter", socket) do
    filtered = filter_projects(socket.assigns.projects, socket.assigns.switcher_query)

    if socket.assigns.switcher_selected >= length(filtered) do
      # "Open another project" selected — go to landing
      socket
      |> assign(:show_project_switcher, false)
      |> push_navigate(to: ~p"/")
    else
      case Enum.at(filtered, socket.assigns.switcher_selected) do
        nil ->
          socket

        project ->
          socket
          |> assign(:show_project_switcher, false)
          |> push_navigate(to: ~p"/projects/#{project.id}")
      end
    end
  end

  defp handle_switcher_hotkey("Escape", socket) do
    assign(socket, :show_project_switcher, false)
  end

  defp handle_switcher_hotkey(_key, socket), do: socket

  defp filter_projects(projects, nil), do: projects
  defp filter_projects(projects, ""), do: projects

  defp filter_projects(projects, query) do
    query_down = String.downcase(query)

    projects
    |> Enum.map(fn p ->
      name = String.downcase(p.name)
      {p, project_match_score(name, query_down)}
    end)
    |> Enum.filter(fn {_p, score} -> score != nil end)
    |> Enum.sort_by(fn {_p, score} -> score end)
    |> Enum.map(fn {p, _score} -> p end)
  end

  # Returns a score (lower is better) or nil if no match.
  # Prefers: exact prefix (0), substring (100), fuzzy with tight gaps (200+gap_penalty).
  defp project_match_score(name, query) do
    cond do
      String.starts_with?(name, query) -> 0
      String.contains?(name, query) -> 100
      fuzzy_match?(name, query) -> 200 + fuzzy_gap_score(name, query)
      true -> nil
    end
  end

  defp fuzzy_match?(name, query) do
    fuzzy_match_chars?(String.graphemes(name), String.graphemes(query))
  end

  defp fuzzy_match_chars?(_name, []), do: true
  defp fuzzy_match_chars?([], _query), do: false
  defp fuzzy_match_chars?([h | t1], [h | t2]), do: fuzzy_match_chars?(t1, t2)
  defp fuzzy_match_chars?([_ | t1], query), do: fuzzy_match_chars?(t1, query)

  # Counts total gaps between matched characters (lower = tighter match)
  defp fuzzy_gap_score(name, query) do
    name_chars = String.graphemes(name)
    query_chars = String.graphemes(query)
    do_gap_score(name_chars, query_chars, 0)
  end

  defp do_gap_score(_name, [], total), do: total
  defp do_gap_score([], _query, _total), do: 999
  defp do_gap_score([h | t1], [h | t2], total), do: do_gap_score(t1, t2, total)
  defp do_gap_score([_ | t1], query, total), do: do_gap_score(t1, query, total + 1)

  # --- Hotkey handlers ---

  defp handle_hotkey("?", socket), do: assign(socket, :show_help, !socket.assigns.show_help)

  defp handle_hotkey("Escape", socket) do
    cond do
      socket.assigns.worktree_mode ->
        assign(socket, :worktree_mode, false)

      socket.assigns.adding_task_to ->
        assign(socket, :adding_task_to, nil)

      socket.assigns.search_mode ->
        socket
        |> assign(:search_mode, false)
        |> assign(:search_query, "")

      socket.assigns.show_project_switcher ->
        assign(socket, :show_project_switcher, false)

      socket.assigns.editing_setting ->
        assign(socket, :editing_setting, nil)

      socket.assigns.pending_action ->
        socket
        |> assign(:pending_action, nil)
        |> clear_flash()
        |> put_flash(:info, "Cancelled")

      socket.assigns.editing_recipe_id ->
        assign(socket, :editing_recipe_id, nil)

      socket.assigns.editing_field ->
        assign(socket, :editing_field, nil)

      socket.assigns.editing_child_id ->
        assign(socket, :editing_child_id, nil)

      socket.assigns.show_preview ->
        socket |> assign(:show_preview, false) |> assign(:preview_port, nil)

      socket.assigns.input_focused ->
        socket
        |> assign(:input_focused, false)
        |> assign(:selected_card, 0)
        |> push_event("blur-input", %{})

      socket.assigns.selected_card == -1 ->
        assign(socket, :selected_card, 0)

      socket.assigns.show_help ->
        assign(socket, :show_help, false)

      socket.assigns.focused_pane == :detail ->
        assign(socket, :focused_pane, :tree)

      socket.assigns.selected_task_id ->
        socket
        |> assign(:focused_pane, :tree)
        |> push_patch(to: project_path(socket))

      true ->
        socket
    end
  end

  defp handle_hotkey("j", socket) do
    cond do
      is_nil(socket.assigns.current_project) ->
        # Landing page: navigate recent projects
        max_idx = max(length(socket.assigns.projects) - 1, 0)
        assign(socket, :selected_card, min(socket.assigns.selected_card + 1, max_idx))

      socket.assigns.focused_pane == :detail ->
        push_event(socket, "scroll-detail", %{direction: "down"})

      true ->
        max_idx = max(length(socket.assigns.card_ids) - 1, 0)
        idx = min(socket.assigns.selected_card + 1, max_idx)

        socket
        |> assign(:selected_card, idx)
        |> maybe_update_adding_task(idx)
        |> push_event("scroll-to-selected", %{})
    end
  end

  defp handle_hotkey("k", socket) do
    cond do
      is_nil(socket.assigns.current_project) ->
        assign(socket, :selected_card, max(socket.assigns.selected_card - 1, 0))

      socket.assigns.focused_pane == :detail ->
        push_event(socket, "scroll-detail", %{direction: "up"})

      socket.assigns.selected_card == 0 ->
        socket
        |> assign(:selected_card, -1)
        |> assign(:adding_task_to, nil)

      true ->
        idx = max(socket.assigns.selected_card - 1, 0)

        socket
        |> assign(:selected_card, idx)
        |> maybe_update_adding_task(idx)
        |> push_event("scroll-to-selected", %{})
    end
  end

  defp handle_hotkey("g", socket) do
    task = socket.assigns.selected_task

    cond do
      is_nil(task) ->
        socket

      task.status in ["brew_done", "done", "closed"] && is_nil(Map.get(task, :pr_url)) &&
          task.git_path ->
        assign(socket, :pending_action, {:local_merge, task.id, task.git_path})

      true ->
        socket
    end
  end

  defp handle_hotkey("G", socket) do
    max_idx = max(length(socket.assigns.card_ids) - 1, 0)
    assign(socket, :selected_card, max_idx)
  end

  defp handle_hotkey("Enter", socket) do
    cond do
      is_nil(socket.assigns.current_project) ->
        if socket.assigns.selected_card >= 0 do
          case Enum.at(socket.assigns.projects, socket.assigns.selected_card) do
            nil -> socket
            project -> push_navigate(socket, to: ~p"/projects/#{project.id}")
          end
        else
          socket
        end

      socket.assigns.selected_card == -1 ->
        push_event(socket, "focus-primary-input", %{})

      true ->
        case Enum.at(socket.assigns.card_ids, socket.assigns.selected_card) do
          nil -> socket
          id -> push_patch(socket, to: project_path(socket) <> "?task=#{id}")
        end
    end
  end

  defp handle_hotkey("l", socket) do
    if is_nil(socket.assigns.current_project) do
      if socket.assigns.selected_card >= 0 do
        case Enum.at(socket.assigns.projects, socket.assigns.selected_card) do
          nil -> socket
          project -> push_navigate(socket, to: ~p"/projects/#{project.id}")
        end
      else
        socket
      end
    else
      # Move focus to detail panel (right)
      assign(socket, :focused_pane, :detail)
    end
  end

  defp handle_hotkey("h", socket) do
    if is_nil(socket.assigns.current_project) do
      socket
    else
      # Move focus to worktree panel (left)
      assign(socket, :focused_pane, :tree)
    end
  end

  defp handle_hotkey("Backspace", socket) do
    if socket.assigns.focused_pane == :detail do
      assign(socket, :focused_pane, :tree)
    else
      if socket.assigns.selected_task_id do
        push_patch(socket, to: project_path(socket))
      else
        socket
      end
    end
  end

  defp handle_hotkey("r", socket) do
    if socket.assigns.selected_task_id do
      case Worktrees.unclaim(socket.assigns.selected_task_id) do
        {:ok, _} ->
          put_flash(socket, :info, "Task requeued")

        {:error, reason} ->
          put_flash(socket, :error, "Failed to requeue: #{inspect(reason)}")
      end
    else
      Worktrees.force_refresh()
      socket
    end
  end

  defp handle_hotkey("s", socket) do
    case socket.assigns.current_project do
      nil ->
        put_flash(socket, :error, "Select a project first")

      project ->
        if socket.assigns.swarm_status == :running do
          Dispatcher.stop_swarm(project.id)
          put_flash(socket, :info, "Brewing stopped")
        else
          Dispatcher.start_swarm(project.id, socket.assigns.target_count)

          put_flash(
            socket,
            :info,
            "Brewing started with #{socket.assigns.target_count} brewers"
          )
        end
    end
  end

  defp handle_hotkey("c", socket) do
    # Focus chat input in chat mode (clear task-add and worktree modes)
    socket
    |> assign(:adding_task_to, nil)
    |> assign(:worktree_mode, false)
    |> assign(:focused_pane, :detail)
    |> push_event("focus-primary-input", %{})
  end

  defp handle_hotkey("/", socket) do
    if is_nil(socket.assigns.current_project) do
      # Landing page: focus the path input
      push_event(socket, "focus-element", %{selector: "#project-path-input"})
    else
      # Focus chat input (same as 'c')
      socket
      |> assign(:focused_pane, :detail)
      |> push_event("focus-primary-input", %{})
    end
  end

  defp handle_hotkey("a", socket) do
    # Focus chat input in task-add mode for focused worktree
    wt_id = socket.assigns.selected_task_id

    socket
    |> then(fn s -> if wt_id, do: assign(s, :adding_task_to, wt_id), else: s end)
    |> assign(:focused_pane, :detail)
    |> push_event("focus-primary-input", %{})
  end

  defp handle_hotkey(key, socket) when key in ["+", "="] do
    handle_brewer_increment(socket)
  end

  defp handle_hotkey("-", socket) do
    handle_brewer_decrement(socket)
  end

  defp handle_hotkey("R", socket) do
    active_ids = active_task_ids_from_agents(socket.assigns.agents)

    {:ok, count} = Worktrees.requeue_all_orphans(active_ids)
    put_flash(socket, :info, "Requeued #{count} orphaned task(s)")
  end

  defp handle_hotkey("q", socket) do
    handle_hotkey("Escape", socket)
  end

  defp handle_hotkey("x", socket) do
    if socket.assigns.selected_task_id do
      case Worktrees.close(socket.assigns.selected_task_id) do
        {:ok, _} ->
          put_flash(socket, :info, "Task closed")

        {:error, reason} ->
          put_flash(socket, :error, "Failed to close: #{inspect(reason)}")
      end
    else
      socket
    end
  end

  defp handle_hotkey("X", socket) do
    # Abort a running brew — find worktree ID from detail panel or hovered card
    wt_id = socket.assigns.selected_task_id || selected_card_id(socket.assigns)

    if wt_id && String.starts_with?(to_string(wt_id), "wt-") do
      case Dispatcher.abort_worktree(wt_id) do
        :ok ->
          put_flash(socket, :info, "Brew aborted on #{wt_id}")

        {:error, :not_found} ->
          put_flash(socket, :error, "No active brew found on #{wt_id}")
      end
    else
      socket
    end
  end

  defp handle_hotkey("m", socket) do
    task = socket.assigns.selected_task

    cond do
      is_nil(task) ->
        socket

      task.status == "pr_open" && Map.get(task, :pr_url) ->
        assign(socket, :pending_action, {:merge, task.id, task.pr_url})

      task.status == "brew_done" && task.git_path ->
        assign(socket, :pending_action, {:direct_merge, task.id, task.git_path})

      true ->
        socket
    end
  end

  defp handle_hotkey("P", socket) do
    case socket.assigns.current_project do
      nil ->
        put_flash(socket, :error, "Select a project first")

      project ->
        lv = self()

        Elixir.Task.start(fn ->
          result =
            case Git.pull_main(project.path) do
              {:ok, output} ->
                {:ok, "Pulled origin main: #{String.trim(output)}"}

              {:error, reason} ->
                {:error, "Pull failed: #{inspect(reason)}"}
            end

          send(lv, {:async_action_result, result})
        end)

        socket
        |> assign(:loading_action, :pulling_main)
        |> put_flash(:info, "Pulling origin main...")
    end
  end

  defp handle_hotkey("p", socket) do
    # Target: open worktree detail panel → that worktree, otherwise → project main
    selected = socket.assigns.selected_task_id
    selected_is_wt = selected && String.starts_with?(to_string(selected), "wt-")

    {target_id, target_type} =
      if selected_is_wt do
        {selected, :worktree}
      else
        case socket.assigns.current_project do
          %{id: id} -> {id, :project}
          _ -> {nil, nil}
        end
      end

    server = target_id && socket.assigns.dev_servers[target_id]

    cond do
      # Toggle preview if already open
      socket.assigns.show_preview ->
        socket |> assign(:show_preview, false) |> assign(:preview_port, nil)

      # Server already running — show preview
      match?(%{status: :running, ports: [_ | _]}, server) ->
        %{ports: ports} = server
        port = if length(ports) == 1, do: hd(ports).port, else: nil
        socket |> assign(:show_preview, true) |> assign(:preview_port, port)

      # Worktree detail open with config — start its server
      target_type == :worktree &&
          (try do
             DevServer.has_config?(target_id)
           catch
             :exit, _ -> false
           end) ->
        DevServer.start_server(target_id)
        socket

      # No worktree detail open, project has config — start main server
      target_type == :project && socket.assigns.has_project_preview_config ->
        project = socket.assigns.current_project
        DevServer.start_project_server(project.id, project.path)
        socket

      socket.assigns.current_project ->
        assign(socket, :show_preview_help, !socket.assigns.show_preview_help)

      true ->
        socket
    end
  end

  defp handle_hotkey("Tab", socket), do: socket

  defp handle_hotkey("ArrowUp", socket) do
    if socket.assigns.selected_task_id do
      task = socket.assigns.selected_task
      current = (task && task.priority) || 3
      new_priority = max(current - 1, 0)

      if new_priority != current do
        Worktrees.update_priority(socket.assigns.selected_task_id, new_priority)
      end

      socket
    else
      socket
    end
  end

  defp handle_hotkey("ArrowDown", socket) do
    if socket.assigns.selected_task_id do
      task = socket.assigns.selected_task
      current = (task && task.priority) || 3
      new_priority = min(current + 1, 4)

      if new_priority != current do
        Worktrees.update_priority(socket.assigns.selected_task_id, new_priority)
      end

      socket
    else
      socket
    end
  end

  defp handle_hotkey("t", socket) do
    path =
      case selected_worktree(socket) do
        %{git_path: gp} when is_binary(gp) and gp != "" ->
          if File.dir?(gp), do: gp, else: nil

        _ ->
          nil
      end

    # Fall back to current project path
    path =
      path ||
        case socket.assigns.current_project do
          %{path: p} when is_binary(p) and p != "" ->
            if File.dir?(p), do: p, else: nil

          _ ->
            nil
        end

    if path do
      System.cmd("open", ["-a", "Terminal", path])
      put_flash(socket, :info, "Opening terminal in #{path}")
    else
      put_flash(socket, :error, "No path found to open terminal")
    end
  end

  defp handle_hotkey("d", socket) do
    case selected_worktree(socket) do
      nil -> socket
      wt -> start_diff_fetch(socket, wt)
    end
  end

  defp handle_hotkey("D", socket) do
    case selected_worktree(socket) do
      nil ->
        socket

      wt ->
        dev = Map.get(socket.assigns.dev_servers, wt.id)

        if dev && dev.status in [:starting, :running] do
          DevServer.stop_server(wt.id)
          put_flash(socket, :info, "Stopping preview for #{wt.id}")
        else
          case DevServer.start_server(wt.id) do
            {:ok, _} -> put_flash(socket, :info, "Starting preview for #{wt.id}")
            {:error, :no_dev_config} -> put_flash(socket, :error, "No .apothecary/preview.yml")
            {:error, reason} -> put_flash(socket, :error, "Preview error: #{inspect(reason)}")
          end
        end
    end
  end

  # Lane jumps: 1=queued, 2=brewing, 3=reviewing, 4=bottled, 5=discarded
  defp handle_hotkey("1", socket), do: jump_to_lane(socket, ~w(ready blocked))
  defp handle_hotkey("2", socket), do: jump_to_lane(socket, ~w(running))
  defp handle_hotkey("3", socket), do: jump_to_lane(socket, ~w(pr))

  defp handle_hotkey("4", socket) do
    new_card_ids =
      build_card_ids(
        socket.assigns.worktrees_by_status,
        false,
        socket.assigns[:collapsed_discarded] != false
      )

    socket
    |> assign(:collapsed_done, false)
    |> assign(:card_ids, new_card_ids)
    |> jump_to_lane(~w(done))
  end

  defp handle_hotkey("5", socket) do
    new_card_ids =
      build_card_ids(
        socket.assigns.worktrees_by_status,
        socket.assigns[:collapsed_done] != false,
        false
      )

    socket
    |> assign(:collapsed_discarded, false)
    |> assign(:card_ids, new_card_ids)
    |> jump_to_lane(~w(discarded))
  end

  # Tab switching: w=workbench, e=recipes
  defp handle_hotkey("w", socket), do: assign(socket, :focused_pane, :tree)
  defp handle_hotkey("e", socket), do: assign(socket, :active_tab, :recipes)

  defp handle_hotkey("b", socket) do
    # Enter worktree creation mode and focus input
    socket
    |> assign(:worktree_mode, true)
    |> assign(:adding_task_to, nil)
    |> assign(:focused_pane, :detail)
    |> push_event("focus-primary-input", %{})
  end

  defp handle_hotkey("n", socket) do
    # Focus right panel input for creating new worktree/task
    socket
    |> assign(:focused_pane, :detail)
    |> push_event("focus-primary-input", %{})
  end

  defp handle_hotkey("J", socket) do
    # Reorder: move selected item down in priority
    # Works from detail panel (selected_task_id) or hovered card (selected_card_id)
    id = socket.assigns.selected_task_id || selected_card_id(socket.assigns)

    if id do
      task = fetch_priority_task(id, socket)
      current = (task && task.priority) || 3
      new_priority = min(current + 1, 4)

      if new_priority != current, do: Worktrees.update_priority(id, new_priority)
      socket
    else
      socket
    end
  end

  defp handle_hotkey("K", socket) do
    # Reorder: move selected item up in priority
    # Works from detail panel (selected_task_id) or hovered card (selected_card_id)
    id = socket.assigns.selected_task_id || selected_card_id(socket.assigns)

    if id do
      task = fetch_priority_task(id, socket)
      current = (task && task.priority) || 3
      new_priority = max(current - 1, 0)

      if new_priority != current, do: Worktrees.update_priority(id, new_priority)
      socket
    else
      socket
    end
  end

  defp handle_hotkey(_key, socket), do: socket

  # --- Brewer/Oracle count helpers ---

  defp handle_brewer_increment(socket) do
    case socket.assigns.current_project do
      nil ->
        socket

      project ->
        count = min(socket.assigns.target_count + 1, 10)

        if socket.assigns.swarm_status == :running do
          Dispatcher.set_agent_count(project.id, count)
        end

        socket = assign(socket, :target_count, count)

        if socket.assigns.swarm_status != :running do
          put_flash(socket, :info, "Brewer count set to #{count}")
        else
          socket
        end
    end
  end

  defp handle_brewer_decrement(socket) do
    case socket.assigns.current_project do
      nil ->
        socket

      project ->
        count = max(socket.assigns.target_count - 1, 1)

        if socket.assigns.swarm_status == :running do
          Dispatcher.set_agent_count(project.id, count)
        end

        socket = assign(socket, :target_count, count)

        if socket.assigns.swarm_status != :running do
          put_flash(socket, :info, "Brewer count set to #{count}")
        else
          socket
        end
    end
  end

  # --- Diff overlay hotkeys ---

  defp handle_diff_hotkey("Escape", socket), do: assign(socket, :diff_view, nil)

  defp handle_diff_hotkey("j", socket) do
    diff = socket.assigns.diff_view
    max_idx = max(length(diff.files) - 1, 0)
    idx = min(diff.selected_file + 1, max_idx)

    socket
    |> assign(:diff_view, %{diff | selected_file: idx})
    |> push_event("scroll-to-diff-file", %{})
  end

  defp handle_diff_hotkey("k", socket) do
    diff = socket.assigns.diff_view
    idx = max(diff.selected_file - 1, 0)

    socket
    |> assign(:diff_view, %{diff | selected_file: idx})
    |> push_event("scroll-to-diff-file", %{})
  end

  defp handle_diff_hotkey(_key, socket), do: socket

  # --- Pending action confirmation ---

  defp handle_pending_action(key, socket) when key in ["m", "y", "Enter"] do
    case socket.assigns.pending_action do
      {:merge, task_id, pr_url} ->
        socket = assign(socket, :pending_action, nil)
        execute_merge(socket, task_id, pr_url)

      {:direct_merge, task_id, git_path} ->
        socket = assign(socket, :pending_action, nil)
        execute_direct_merge(socket, task_id, git_path)

      {:local_merge, task_id, git_path} ->
        socket = assign(socket, :pending_action, nil)
        execute_local_merge(socket, task_id, git_path)

      _ ->
        assign(socket, :pending_action, nil)
    end
  end

  defp handle_pending_action("Escape", socket) do
    socket
    |> assign(:pending_action, nil)
    |> clear_flash()
  end

  defp handle_pending_action(_key, socket) do
    socket
    |> assign(:pending_action, nil)
    |> clear_flash()
  end

  defp execute_merge(socket, task_id, pr_url) do
    project_dir = resolve_project_dir_for_worktree(task_id)
    lv = self()

    Elixir.Task.start(fn ->
      result =
        case Git.merge_pr(project_dir, pr_url) do
          :ok ->
            Worktrees.add_note(task_id, "PR merged from dashboard: #{pr_url}")
            Worktrees.cleanup_merged_worktree(task_id)
            {:ok, "PR merged and worktree cleaned up"}

          {:error, reason} ->
            {:error, "Merge failed: #{inspect(reason)}"}
        end

      send(lv, {:async_action_result, result})
    end)

    assign(socket, :loading_action, :merging)
  end

  defp execute_direct_merge(socket, task_id, git_path) do
    project_dir = resolve_project_dir_for_worktree(task_id)
    task = socket.assigns.selected_task
    title = "[#{task_id}] #{(task && task.title) || task_id}"
    lv = self()

    Elixir.Task.start(fn ->
      result =
        with {:ok, pr_url} <- Git.create_pr(project_dir, git_path, title),
             :ok <- Git.merge_pr(project_dir, pr_url) do
          Worktrees.add_note(
            task_id,
            "Direct merge from dashboard (PR created and merged): #{pr_url}"
          )

          Worktrees.update_worktree(task_id, %{pr_url: pr_url})
          Worktrees.cleanup_merged_worktree(task_id)
          {:ok, "PR created and merged: #{pr_url}"}
        else
          {:error, reason} ->
            Worktrees.add_note(task_id, "Direct merge failed: #{inspect(reason)}")
            {:error, "Direct merge failed: #{inspect(reason)}"}
        end

      send(lv, {:async_action_result, result})
    end)

    assign(socket, :loading_action, :direct_merging)
  end

  defp execute_local_merge(socket, task_id, git_path) do
    project_dir = resolve_project_dir_for_worktree(task_id)
    lv = self()

    Elixir.Task.start(fn ->
      result =
        case Git.local_merge(project_dir, git_path) do
          :ok ->
            Worktrees.add_note(task_id, "Merged locally via git (no PR)")
            Worktrees.cleanup_merged_worktree(task_id)
            {:ok, "Branch merged locally into main"}

          {:error, {:merge_conflict, output}} ->
            Worktrees.add_note(task_id, "Local merge failed: merge conflict")
            {:error, "Merge conflict: #{output}"}

          {:error, reason} ->
            {:error, "Local merge failed: #{inspect(reason)}"}
        end

      send(lv, {:async_action_result, result})
    end)

    assign(socket, :loading_action, :local_merging)
  end

  # --- Promote brew_done to assaying (create PR) ---

  defp promote_to_assaying(socket, task) do
    task_id = task.id
    git_path = task.git_path
    project_dir = resolve_project_dir_for_worktree(task_id)

    if git_path do
      title = "[#{task_id}] #{task.title}"
      lv = self()

      Elixir.Task.start(fn ->
        result =
          case Git.create_pr(project_dir, git_path, title) do
            {:ok, pr_url} ->
              Worktrees.add_note(task_id, "PR created from dashboard: #{pr_url}")

              Worktrees.update_worktree(task_id, %{
                status: "pr_open",
                pr_url: pr_url
              })

              {:ok, "PR created: #{pr_url}"}

            {:error, reason} ->
              Worktrees.add_note(
                task_id,
                "PR creation failed: #{inspect(reason)}. Try again or create manually."
              )

              {:error, "PR creation failed: #{inspect(reason)}"}
          end

        send(lv, {:async_action_result, result})
      end)

      assign(socket, :loading_action, :creating_pr)
    else
      put_flash(socket, :error, "No git path found for this worktree")
    end
  end

  # --- Diff fetch ---

  defp selected_worktree(socket) do
    case Enum.at(socket.assigns.card_ids, socket.assigns.selected_card) do
      nil ->
        nil

      id ->
        socket.assigns.worktrees_by_status
        |> Enum.find_value(fn {_group, entries} ->
          Enum.find(entries, fn entry -> entry.worktree.id == id end)
        end)
        |> case do
          nil -> nil
          entry -> entry.worktree
        end
    end
  end

  defp start_diff_fetch(socket, wt) do
    lv = self()
    wt_id = wt.id
    pr_url = Map.get(wt, :pr_url)
    git_path = Map.get(wt, :git_path)
    project_dir = resolve_project_dir_for_worktree(wt_id)

    diff_view = %{
      files: [],
      selected_file: 0,
      worktree_id: wt_id,
      loading: true,
      error: nil
    }

    Elixir.Task.start(fn ->
      result =
        try do
          fetch_diff(pr_url, git_path, project_dir)
        rescue
          e -> {:error, Exception.message(e)}
        end

      send(lv, {:diff_result, wt_id, result})
    end)

    assign(socket, :diff_view, diff_view)
  end

  defp fetch_diff(pr_url, git_path, project_dir) do
    with {:error, _} <- try_pr_diff(pr_url, project_dir),
         {:error, _} <- try_worktree_diff(git_path, project_dir) do
      {:error, "No diff available (no PR URL or worktree path)"}
    end
  end

  defp try_pr_diff(pr_url, project_dir) when is_binary(pr_url) and pr_url != "" do
    Git.pr_diff(project_dir, pr_url)
  end

  defp try_pr_diff(_, _), do: {:error, :no_pr_url}

  defp try_worktree_diff(git_path, project_dir) when is_binary(git_path) and git_path != "" do
    if File.dir?(git_path) do
      Git.worktree_diff(project_dir, git_path)
    else
      {:error, :worktree_not_found}
    end
  end

  defp try_worktree_diff(_, _), do: {:error, :no_git_path}

  # --- Input handlers ---

  defp create_question_for_worktree(text, socket) do
    question_text = text |> String.trim_leading("?") |> String.trim()

    if question_text == "" do
      {:noreply, socket}
    else
      # Use the focused worktree as context
      worktree_id = socket.assigns.adding_task_to || socket.assigns.selected_task_id

      project_id =
        if socket.assigns.current_project, do: socket.assigns.current_project.id, else: nil

      attrs = %{
        title: question_text,
        kind: "question",
        priority: 2,
        project_id: project_id
      }

      attrs =
        if worktree_id, do: Map.put(attrs, :parent_worktree_id, worktree_id), else: attrs

      case Worktrees.create_worktree(attrs) do
        {:ok, item} when not is_nil(item) ->
          # Dispatch immediately with a one-off brewer
          if project_id do
            Dispatcher.dispatch_question(project_id, item.id)
          end

          {:noreply, put_flash(socket, :info, "Question submitted")}

        {:ok, nil} ->
          {:noreply, put_flash(socket, :error, "Failed to submit question")}

        {:error, reason} ->
          {:noreply, put_flash(socket, :error, "Failed: #{inspect(reason)}")}
      end
    end
  end

  defp send_to_agent(text, images, socket) do
    agent = socket.assigns.working_agent

    if agent && agent.pid do
      # Build message with image paths if any were attached
      message =
        case images do
          [] ->
            text

          paths ->
            image_refs = Enum.map_join(paths, "\n", &"[image: #{&1}]")
            if text == "", do: image_refs, else: "#{text}\n#{image_refs}"
        end

      Brewer.send_instruction(agent.pid, message)

      # Show user message in the activity stream
      image_count = length(images)

      user_line =
        cond do
          image_count > 0 && text != "" -> "▸ you: #{text} [#{image_count} image(s)]"
          image_count > 0 -> "▸ you: [#{image_count} image(s)]"
          true -> "▸ you: #{text}"
        end

      output = (socket.assigns.agent_output ++ [user_line]) |> Enum.take(-200)

      {:noreply,
       socket
       |> assign(:agent_output, output)
       |> put_flash(:info, "Sent to agent")}
    else
      {:noreply, put_flash(socket, :error, "No active agent process")}
    end
  end

  # --- Task selection ---

  defp select_task(socket, nil) do
    old_agent = socket.assigns[:working_agent]
    if old_agent, do: Phoenix.PubSub.unsubscribe(@pubsub, "brewer:#{old_agent.id}")

    socket
    |> assign(:selected_task_id, nil)
    |> assign(:selected_task, nil)
    |> assign(:children, [])
    |> assign(:editing_field, nil)
    |> assign(:editing_child_id, nil)
    |> assign(:working_agent, nil)
    |> assign(:agent_output, [])
    |> assign(:show_preview, false)
    |> assign(:preview_port, nil)
    |> assign(:focused_pane, :tree)
    |> assign(:page_title, "Dashboard")
  end

  defp select_task(socket, id) do
    old_agent = socket.assigns[:working_agent]
    if old_agent, do: Phoenix.PubSub.unsubscribe(@pubsub, "brewer:#{old_agent.id}")

    task =
      case Worktrees.show(id) do
        {:ok, task} -> task
        {:error, _} -> nil
      end

    {:ok, children} = Worktrees.children(id)

    has_preview =
      if String.starts_with?(to_string(id), "wt-") do
        try do
          DevServer.has_config?(id)
        catch
          :exit, _ -> false
        end
      else
        false
      end

    # Refresh project-level preview config (file may have been added since load)
    has_project_preview =
      case socket.assigns[:current_project] do
        %{path: path} -> DevServer.has_config_for_path?(path)
        _ -> socket.assigns[:has_project_preview_config] || false
      end

    wt_id = if String.starts_with?(to_string(id), "wt-"), do: id, else: nil

    socket
    |> assign(:selected_task_id, id)
    |> assign(:selected_task, task)
    |> assign(:children, children)
    |> assign(:editing_field, nil)
    |> assign(:editing_child_id, nil)
    |> assign(:working_agent, nil)
    |> assign(:agent_output, [])
    |> assign(:show_preview, false)
    |> assign(:preview_port, nil)
    |> assign(:has_preview_config, has_preview)
    |> assign(:has_project_preview_config, has_project_preview)
    |> assign(:adding_task_to, wt_id)
    |> assign(:page_title, "Task #{id}")
    |> sync_selected_card(id)
    |> find_working_agent()
  end

  defp sync_selected_card(socket, id) do
    case Enum.find_index(socket.assigns.card_ids, &(&1 == id)) do
      nil -> socket
      idx -> assign(socket, :selected_card, idx)
    end
  end

  defp refresh_selected_task(socket) do
    id = socket.assigns.selected_task_id

    task =
      case Worktrees.show(id) do
        {:ok, task} -> task
        {:error, _} -> nil
      end

    {:ok, children} = Worktrees.children(id)

    socket
    |> assign(:selected_task, task)
    |> assign(:children, children)
  end

  defp find_working_agent(socket) do
    task_id = socket.assigns.selected_task_id

    agent =
      socket.assigns.agents
      |> Enum.find(fn a ->
        a.current_worktree && to_string(a.current_worktree.id) == to_string(task_id)
      end)

    old_agent = socket.assigns.working_agent

    socket =
      if agent do
        if is_nil(old_agent) || old_agent.id != agent.id do
          if old_agent, do: Phoenix.PubSub.unsubscribe(@pubsub, "brewer:#{old_agent.id}")
          Phoenix.PubSub.subscribe(@pubsub, "brewer:#{agent.id}")
          assign(socket, :agent_output, agent.output || [])
        else
          socket
        end
      else
        if old_agent, do: Phoenix.PubSub.unsubscribe(@pubsub, "brewer:#{old_agent.id}")
        socket
      end

    assign(socket, :working_agent, agent)
  end

  # --- Worktree grouping (card-based) ---

  defp build_worktree_groups(all_items, agents, dev_servers) do
    {worktrees, tasks} =
      Enum.split_with(all_items, fn item ->
        String.starts_with?(to_string(item.id), "wt-")
      end)

    tasks_by_wt =
      Enum.group_by(tasks, fn t ->
        t.worktree_id || t.parent
      end)

    agent_by_wt =
      agents
      |> Enum.filter(& &1.current_worktree)
      |> Map.new(fn a -> {to_string(a.current_worktree.id), a} end)

    active_wt_ids =
      agents
      |> Enum.flat_map(fn a ->
        if a.current_worktree, do: [to_string(a.current_worktree.id)], else: []
      end)
      |> MapSet.new()

    groups =
      Enum.group_by(worktrees, fn wt ->
        cond do
          MapSet.member?(active_wt_ids, to_string(wt.id)) -> "running"
          wt.status == "brew_done" -> "pr"
          wt.status in ["open", "ready"] -> "ready"
          wt.status in ["in_progress", "claimed"] -> "ready"
          wt.status in ["blocked", "merge_conflict"] -> "blocked"
          wt.status == "pr_open" -> "pr"
          wt.status == "revision_needed" -> "ready"
          wt.status == "merged" -> "done"
          wt.status in ["done", "closed", "cancelled"] -> "discarded"
          true -> "ready"
        end
      end)

    Map.new(@group_order, fn group ->
      wts =
        (groups[group] || [])
        |> Enum.sort_by(fn wt -> {wt.priority || 99, wt.created_at || ""} end)
        |> Enum.map(fn wt ->
          wt_tasks =
            (tasks_by_wt[wt.id] || [])
            |> Enum.sort_by(fn t ->
              done = if t.status in ["done", "closed"], do: 1, else: 0
              {done, t.priority || 99, t.created_at || ""}
            end)

          %{
            worktree: wt,
            tasks: wt_tasks,
            agent: agent_by_wt[wt.id],
            dev_server: dev_servers[wt.id]
          }
        end)

      {group, wts}
    end)
  end

  # --- Helpers ---

  defp save_uploaded_image(data, mime, name) do
    ext =
      case mime do
        "image/png" -> ".png"
        "image/jpeg" -> ".jpg"
        "image/gif" -> ".gif"
        "image/webp" -> ".webp"
        _ -> Path.extname(name)
      end

    uploads_dir = Path.join([System.get_env("HOME") || "/tmp", ".apothecary", "uploads"])
    File.mkdir_p!(uploads_dir)
    filename = "paste-#{System.unique_integer([:positive])}#{ext}"
    path = Path.join(uploads_dir, filename)

    case Base.decode64(data) do
      {:ok, binary} ->
        File.write!(path, binary)
        {:ok, path}

      :error ->
        :error
    end
  end

  defp build_description_with_images(text, images) do
    case images do
      [] ->
        if text != "", do: text, else: nil

      paths ->
        image_lines = Enum.map_join(paths, "\n", &"[image: #{&1}]")
        if text != "", do: "#{text}\n#{image_lines}", else: image_lines
    end
  end

  defp fetch_priority_task(id, socket) do
    if id == socket.assigns.selected_task_id do
      socket.assigns.selected_task
    else
      case Worktrees.show(id) do
        {:ok, t} -> t
        _ -> nil
      end
    end
  end

  defp worktree_id_at(card_ids, idx) do
    case Enum.at(card_ids, idx) do
      nil -> nil
      id -> if String.starts_with?(to_string(id), "wt-"), do: id, else: nil
    end
  end

  # Only move adding_task_to target if already in task-add mode (via 'a' hotkey)
  defp maybe_update_adding_task(socket, idx) do
    if socket.assigns.adding_task_to do
      assign(socket, :adding_task_to, worktree_id_at(socket.assigns.card_ids, idx))
    else
      socket
    end
  end

  defp load_project_files(nil) do
    case Projects.list_active() do
      [project | _] ->
        case FileTree.list_files(project.path) do
          {:ok, files} -> files
          {:error, _} -> []
        end

      [] ->
        []
    end
  end

  defp load_project_files(%{path: path}) do
    case FileTree.list_files(path) do
      {:ok, files} -> files
      {:error, _} -> []
    end
  end

  defp expand_tilde("~/" <> rest), do: Path.join(System.get_env("HOME", "~"), rest)
  defp expand_tilde("~"), do: System.get_env("HOME", "~")
  defp expand_tilde(path), do: path

  defp list_path_suggestions(input) do
    input = String.trim(input)

    # If input is itself a valid git repo directory, no suggestions needed
    if File.dir?(input) and File.dir?(Path.join(input, ".git")) do
      []
    else
      {dir, query} =
        if String.ends_with?(input, "/") do
          {input, ""}
        else
          {Path.dirname(input), Path.basename(input)}
        end

      case File.ls(dir) do
        {:ok, entries} ->
          entries
          |> Enum.filter(fn name -> not String.starts_with?(name, ".") end)
          |> Enum.map(fn name -> Path.join(dir, name) end)
          |> Enum.filter(&File.dir?/1)
          |> Enum.map(fn full_path ->
            name = Path.basename(full_path)
            score = fuzzy_score(String.downcase(query), String.downcase(name))
            {full_path, name, score}
          end)
          |> Enum.filter(fn {_, _, score} -> score > 0 or query == "" end)
          |> Enum.sort_by(fn {_, name, score} -> {-score, name} end)
          |> Enum.take(8)
          |> Enum.map(fn {full_path, name, _score} ->
            %{
              path: full_path,
              name: name,
              is_git: File.dir?(Path.join(full_path, ".git"))
            }
          end)

        {:error, _} ->
          []
      end
    end
  end

  # Fuzzy match: checks if all chars in query appear in name in order.
  # Returns a score (higher = better). 0 = no match.
  defp fuzzy_score("", _name), do: 1
  defp fuzzy_score(_query, ""), do: 0

  defp fuzzy_score(query, name) do
    query_chars = String.graphemes(query)
    name_chars = String.graphemes(name)

    case match_chars(query_chars, name_chars, 0, 0) do
      nil ->
        0

      {matched, consecutive_bonus} ->
        # Boost: consecutive matches, prefix matches, length similarity
        prefix_bonus = if String.starts_with?(name, query), do: 10, else: 0
        matched + consecutive_bonus * 2 + prefix_bonus
    end
  end

  defp match_chars([], _name, matched, consecutive), do: {matched, consecutive}
  defp match_chars(_query, [], _matched, _consecutive), do: nil

  defp match_chars([q | qrest], [n | nrest], matched, consecutive) do
    if q == n do
      match_chars(qrest, nrest, matched + 1, consecutive + 1)
    else
      match_chars([q | qrest], nrest, matched, 0)
    end
  end

  defp scoped_get_state(socket) do
    case socket.assigns.current_project do
      nil -> Worktrees.get_state()
      project -> Worktrees.get_state(project_id: project.id)
    end
  end

  defp project_path(socket, extra \\ "") do
    case socket.assigns.current_project do
      nil -> "/" <> extra
      project -> "/projects/#{project.id}" <> if(extra != "", do: "/" <> extra, else: "")
    end
  end

  defp filter_state_for_project(state, nil), do: state

  defp filter_state_for_project(state, project) do
    # Get project's worktree IDs
    project_worktree_ids =
      state.tasks
      |> Enum.filter(fn item ->
        String.starts_with?(to_string(item.id), "wt-") and
          Map.get(item, :project_id) == project.id
      end)
      |> MapSet.new(& &1.id)

    tasks =
      Enum.filter(state.tasks, fn item ->
        if String.starts_with?(to_string(item.id), "wt-") do
          MapSet.member?(project_worktree_ids, item.id)
        else
          MapSet.member?(project_worktree_ids, item.worktree_id)
        end
      end)

    %{state | tasks: tasks}
  end

  defp resolve_project_dir_for_worktree(worktree_id) do
    case Worktrees.get_worktree(worktree_id) do
      {:ok, %{project_id: project_id}} when not is_nil(project_id) ->
        case Apothecary.Projects.get(project_id) do
          {:ok, project} -> project.path
          _ -> nil
        end

      _ ->
        nil
    end
  end

  defp jump_to_lane(socket, groups) do
    # Find the first card_id that belongs to one of the given groups
    lane_ids =
      groups
      |> Enum.flat_map(fn g -> socket.assigns.worktrees_by_status[g] || [] end)
      |> Enum.map(fn e -> e.worktree.id end)
      |> MapSet.new()

    case Enum.find_index(socket.assigns.card_ids, &MapSet.member?(lane_ids, &1)) do
      nil ->
        socket

      idx ->
        socket
        |> assign(:selected_card, idx)
        |> push_event("scroll-to-selected", %{})
    end
  end

  defp build_card_ids(worktrees_by_status, collapsed_done, collapsed_discarded) do
    sort_by_priority = fn entries ->
      entries
      |> Enum.sort_by(fn e -> e.worktree.priority || 99 end)
      |> Enum.map(fn e -> e.worktree.id end)
    end

    stockroom =
      Enum.flat_map(~w(ready blocked), fn g -> worktrees_by_status[g] || [] end)
      |> sort_by_priority.()

    brewing =
      (worktrees_by_status["running"] || []) |> sort_by_priority.()

    assaying =
      (worktrees_by_status["pr"] || []) |> sort_by_priority.()

    done =
      if collapsed_done do
        []
      else
        (worktrees_by_status["done"] || [])
        |> Enum.map(fn e -> e.worktree.id end)
      end

    discarded =
      if collapsed_discarded do
        []
      else
        (worktrees_by_status["discarded"] || [])
        |> Enum.map(fn e -> e.worktree.id end)
      end

    brewing ++ assaying ++ stockroom ++ done ++ discarded
  end

  defp rebuild_card_ids(socket, worktrees_by_status) do
    old_card_ids = socket.assigns.card_ids
    old_selected_id = Enum.at(old_card_ids, socket.assigns.selected_card)

    new_card_ids =
      build_card_ids(
        worktrees_by_status,
        socket.assigns.collapsed_done,
        socket.assigns[:collapsed_discarded] != false
      )

    found_idx =
      if old_selected_id do
        Enum.find_index(new_card_ids, &(&1 == old_selected_id))
      end

    idx =
      if found_idx do
        found_idx
      else
        min(socket.assigns.selected_card, max(length(new_card_ids) - 1, 0))
      end

    socket =
      socket
      |> assign(:card_ids, new_card_ids)
      |> assign(:selected_card, idx)

    # If old selection disappeared (moved to collapsed group), select the card at the new index
    new_selected_id = Enum.at(new_card_ids, idx)

    cond do
      is_nil(found_idx) && old_selected_id && new_selected_id &&
          new_selected_id != socket.assigns[:selected_task_id] ->
        select_task(socket, new_selected_id)

      is_nil(found_idx) && old_selected_id && is_nil(new_selected_id) ->
        select_task(socket, nil)

      true ->
        socket
    end
  end

  defp find_entry_by_id(worktrees_by_status, card_id) do
    Enum.find_value(worktrees_by_status, fn {_status, entries} ->
      Enum.find(entries, fn e -> e.worktree.id == card_id end)
    end)
  end

  defp extract_task_ids(tasks) do
    tasks
    |> Enum.filter(&String.starts_with?(to_string(&1.id), "t-"))
    |> MapSet.new(& &1.id)
  end

  defp compute_orphan_count(tasks, active_task_ids) do
    active_set = MapSet.new(active_task_ids, &to_string/1)

    Enum.count(tasks, fn t ->
      t.status in ["in_progress", "claimed"] and not MapSet.member?(active_set, to_string(t.id))
    end)
  end

  defp active_task_ids_from_agents(agents) do
    Enum.flat_map(agents, fn a ->
      if Map.get(a, :current_worktree), do: [a.current_worktree.id], else: []
    end)
  end

  defp subscribe_to_agents(agents) do
    Enum.each(agents, fn agent ->
      Phoenix.PubSub.subscribe(@pubsub, "brewer:#{agent.id}")
    end)
  end

  defp update_agent_subscriptions(old_agents, new_agents) do
    old_ids = MapSet.new(old_agents, & &1.id)
    new_ids = MapSet.new(new_agents, & &1.id)

    new_agents
    |> Enum.filter(fn a -> not MapSet.member?(old_ids, a.id) end)
    |> Enum.each(fn a -> Phoenix.PubSub.subscribe(@pubsub, "brewer:#{a.id}") end)

    old_agents
    |> Enum.filter(fn a -> not MapSet.member?(new_ids, a.id) end)
    |> Enum.each(fn a -> Phoenix.PubSub.unsubscribe(@pubsub, "brewer:#{a.id}") end)
  end

  defp current_project_swarm_status(socket, dispatcher_status) do
    case socket.assigns.current_project do
      nil ->
        # No project selected — show aggregate
        %{
          status: dispatcher_status.status,
          target_count: dispatcher_status.target_count,
          active_count: dispatcher_status.active_count
        }

      project ->
        projects = dispatcher_status[:projects] || %{}

        case projects[project.id] do
          nil ->
            %{
              status: :paused,
              target_count: 0,
              active_count: 0
            }

          ps ->
            ps
        end
    end
  end

  defp enrich_agents_with_pids(agents_map) do
    Enum.map(agents_map, fn {pid, agent_state} ->
      Map.put(agent_state, :pid, pid)
    end)
  end

  defp selected_card_id(assigns) do
    Enum.at(assigns.card_ids, assigns.selected_card)
  end

  @impl true
  def render(assigns) do
    assigns = assign(assigns, :selected_card_id, selected_card_id(assigns))

    ~H"""
    <Layouts.app flash={@flash}>
      <div
        id="hotkey-root"
        phx-hook="DashboardKeys"
        phx-window-keydown="hotkey"
        phx-keydown="hotkey"
        tabindex="0"
        phx-throttle="100"
        class="flex flex-col h-screen outline-none"
        data-theme={@theme}
      >
        <%!-- Top bar --%>
        <.top_bar
          current_project={@current_project}
          active_tab={@active_tab}
          selected_task_id={@selected_task_id}
          selected_task={@selected_task}
          projects={@projects}
          show_project_switcher={@show_project_switcher}
          worktrees_by_status={@worktrees_by_status}
          theme={@theme}
        />

        <div style="border-bottom: 1px solid var(--border);" />

        <%!-- Project switcher overlay --%>
        <.project_switcher
          :if={@show_project_switcher}
          projects={filter_projects(@projects, @switcher_query)}
          current_project={@current_project}
          dispatcher_projects={@dispatcher_projects}
          selected_index={@switcher_selected}
          query={@switcher_query}
        />

        <%!-- Main content area --%>
        <div class="flex-1 overflow-hidden">
          <%= cond do %>
            <% is_nil(@current_project) -> %>
              <div class="h-full overflow-y-auto scroll-main">
                <div class="max-w-[540px] mx-auto">
                  <.project_landing
                    projects={@projects}
                    project_path_suggestions={@project_path_suggestions}
                    add_project_error={@add_project_error}
                    selected_project={@selected_card}
                  />
                </div>
              </div>
            <% @active_tab == :recipes -> %>
              <div class="h-full overflow-y-auto scroll-main">
                <div class="max-w-[540px] mx-auto">
                  <.recipe_list
                    recipes={@recipes}
                    show_recipe_form={@show_recipe_form}
                    recipe_form={@recipe_form}
                    editing_recipe_id={@editing_recipe_id}
                  />
                </div>
              </div>
            <% @active_tab == :workbench -> %>
              <%!-- Split panel: worktree list left, detail + preview right --%>
              <div class="flex h-full">
                <%!-- Left panel: worktree tree (hidden on small screens when preview open) --%>
                <div
                  id="worktree-panel"
                  class={"h-full overflow-y-auto scroll-main flex-shrink-0 flex flex-col#{if @show_preview, do: " hidden-when-narrow", else: ""}"}
                  style="width: 280px; min-width: 220px; max-width: 400px; border-right: 1px solid var(--border);"
                  phx-click="focus-tree-pane"
                >
                  <div class="flex-1 overflow-y-auto scroll-main">
                    <.settings_line
                      target_count={@target_count}
                      auto_pr={@auto_pr}
                      swarm_status={@swarm_status}
                      agents={@agents}
                      dev_server={@dev_servers[@current_project && @current_project.id]}
                      has_preview_config={@has_project_preview_config}
                      project_id={@current_project && @current_project.id}
                      editing_setting={@editing_setting}
                      show_preview_help={@show_preview_help}
                    />

                    <.worktree_tree
                      worktrees_by_status={@worktrees_by_status}
                      agents={@agents}
                      dev_servers={@dev_servers}
                      selected_card={@selected_card}
                      card_ids={@card_ids}
                      collapsed_done={@collapsed_done}
                      collapsed_discarded={@collapsed_discarded}
                      adding_task_to={@adding_task_to}
                      search_mode={@search_mode}
                      search_query={@search_query}
                    />

                    <%!-- Open existing worktree button --%>
                    <div class="px-3 py-2">
                      <button
                        phx-click="show-adopt-worktree"
                        class="cursor-pointer w-full text-left"
                        style="color: var(--muted); font-size: var(--font-size-xs); padding: 4px 6px; border: 1px dashed var(--border); border-radius: 4px;"
                      >
                        + open existing worktree
                      </button>
                    </div>
                  </div>
                </div>

                <%!-- Resize handle (hidden when preview open) --%>
                <div
                  :if={!@show_preview}
                  id="resize-handle"
                  phx-hook="ResizeHandle"
                  class="resize-handle"
                />

                <%!-- Middle panel: focused worktree detail + chat input --%>
                <div
                  id="detail-pane"
                  class="flex-1 flex flex-col h-full min-w-0"
                  style="border-top: 2px solid transparent;"
                  phx-click="focus-detail-pane"
                >
                  <div class="flex-1 overflow-y-auto scroll-main">
                    <%= if @selected_task && @selected_task_id do %>
                      <.worktree_detail
                        task={@selected_task}
                        children={@children}
                        editing_field={@editing_field}
                        editing_child_id={@editing_child_id}
                        working_agent={@working_agent}
                        agent_output={@agent_output}
                        dev_server={@dev_servers[@selected_task_id]}
                        has_preview_config={@has_preview_config}
                        pending_action={@pending_action}
                        loading_action={@loading_action}
                        worktree_questions={
                          Enum.filter(@questions, fn q ->
                            Map.get(q, :parent_worktree_id) == @selected_task_id
                          end)
                        }
                        follow_up_question_id={@follow_up_question_id}
                      />
                    <% else %>
                      <div
                        class="h-full flex items-center justify-center"
                        style="color: var(--muted); font-size: var(--font-size-sm);"
                      >
                        <div class="text-center">
                          <div
                            class="flex items-center justify-center gap-2 mb-4"
                            style="font-size: 20px; color: var(--dim);"
                          >
                            <span>&#x25C7;</span>
                            <span style="color: var(--muted);">&#x2500;</span>
                            <span>&#x25C7;</span>
                          </div>
                          <div class="mb-4" style="color: var(--dim);">
                            select a worktree to focus
                          </div>
                          <div class="mb-1" style="font-size: var(--font-size-xs);">
                            <span style="font-weight: 600;">j/k</span>
                            navigate <span style="color: var(--border);">&nbsp;&middot;&nbsp;</span>
                            <span style="font-weight: 600;">enter</span>
                            focus
                          </div>
                          <div class="mb-1" style="font-size: var(--font-size-xs);">
                            <span style="font-weight: 600;">c</span>
                            chat <span style="color: var(--border);">&nbsp;&middot;&nbsp;</span>
                            <span style="font-weight: 600;">w</span>
                            branches
                          </div>
                        </div>
                      </div>
                    <% end %>
                  </div>
                  <%!-- Chat input at bottom --%>
                  <.chat_input
                    input_focused={@input_focused}
                    selected_card_id={@selected_card_id}
                    adding_task_to={@adding_task_to}
                    working_agent={@working_agent}
                    worktree_mode={@worktree_mode}
                  />
                </div>

                <%!-- Right panel: preview (only when open) --%>
                <%= if @show_preview do %>
                  <div
                    id="preview-panel"
                    class="h-full flex-shrink-0 flex flex-col"
                    style="width: 55%; min-width: 400px; border-left: 1px solid var(--border);"
                  >
                    <.preview_panel
                      port={@preview_port}
                      dev_servers={@dev_servers}
                      current_project={@current_project}
                      show_logs={@show_preview_logs}
                      worktrees_by_status={@worktrees_by_status}
                    />
                  </div>
                <% end %>
              </div>
            <% true -> %>
          <% end %>
        </div>

        <%!-- Status bar --%>
        <.moonlight_status_bar
          selected_task={@selected_task}
          selected_task_id={@selected_task_id}
          worktrees_by_status={@worktrees_by_status}
          orphan_count={@orphan_count}
          current_project={@current_project}
          active_tab={@active_tab}
          show_project_switcher={@show_project_switcher}
          project_count={length(@projects)}
          questions={@questions}
          agents={@agents}
          input_focused={@input_focused}
          focused_pane={@focused_pane}
        />
      </div>

      <%!-- Overlays --%>
      <.which_key_overlay
        :if={@show_help}
        page={:dashboard}
        has_selected_task={@selected_task_id != nil}
      />

      <.diff_overlay :if={@diff_view} diff_view={@diff_view} />

      <.new_project_modal
        :if={@show_new_project}
        error={@new_project_error}
        progress={@bootstrap_progress}
      />

      <.adopt_worktree_modal
        :if={@show_adopt_worktree}
        error={@adopt_worktree_error}
        disk_worktrees={@adopt_disk_worktrees}
      />
    </Layouts.app>
    """
  end
end
