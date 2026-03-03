defmodule ApothecaryWeb.DashboardLive do
  use ApothecaryWeb, :live_view

  alias Apothecary.{
    Brewer,
    DevServer,
    DiffParser,
    FileTree,
    Git,
    Ingredients,
    Dispatcher,
    Projects
  }

  @pubsub Apothecary.PubSub

  @group_order ~w(running ready blocked pr done)

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      Ingredients.subscribe()
      Ingredients.subscribe_recipes()
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
      |> assign(:selected_card, 0)
      # Panel state
      |> assign(:selected_task_id, nil)
      |> assign(:selected_task, nil)
      |> assign(:children, [])
      |> assign(:editing_field, nil)
      |> assign(:working_agent, nil)
      |> assign(:agent_output, [])
      |> assign(:diff_view, nil)
      |> assign(:pending_action, nil)
      # Tab navigation
      |> assign(:active_tab, :workbench)
      # Recipe state
      |> assign(:recipes, Ingredients.list_recipes())
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
      # Add project modal
      |> assign(:show_add_project, false)
      |> assign(:add_project_error, nil)
      |> assign(:project_path_suggestions, [])
      # New project (bootstrap) modal
      |> assign(:show_new_project, false)
      |> assign(:new_project_error, nil)
      |> assign(:bootstrap_progress, nil)
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
    # Auto-select first project when none is selected
    case socket.assigns.projects do
      [first | _] when is_nil(socket.assigns.current_project) ->
        {:noreply, push_navigate(socket, to: ~p"/projects/#{first.id}")}

      _ ->
        socket = apply_project_scope(socket, nil)
        {:noreply, select_task(socket, nil)}
    end
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
        Ingredients.get_state(project_id: project.id)
      else
        Ingredients.get_state()
      end

    agents = socket.assigns[:agents] || []
    dev_servers = socket.assigns[:dev_servers] || %{}
    active_task_ids = active_task_ids_from_agents(agents)

    # Separate questions from task concoctions
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
    |> assign(:card_ids, build_card_ids(worktrees_by_status))
    |> assign(:known_ingredient_ids, extract_ingredient_ids(task_state.tasks))
    |> assign(:project_files, load_project_files(project))
    |> assign(:questions, questions)
  end

  # --- PubSub handlers ---

  @impl true
  def handle_info({:ingredients_update, state}, socket) do
    # Re-filter state if scoped to a project
    state = filter_state_for_project(state, socket.assigns.current_project)

    new_ids = extract_ingredient_ids(state.tasks)
    old_ids = socket.assigns.known_ingredient_ids
    created = MapSet.difference(new_ids, old_ids)

    socket =
      if MapSet.size(created) > 0 do
        new_ingredients = Enum.filter(state.tasks, &MapSet.member?(created, &1.id))
        names = Enum.map_join(new_ingredients, ", ", & &1.title)
        put_flash(socket, :info, "Ingredient added: #{names}")
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
      |> assign(:known_ingredient_ids, new_ids)
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

    {:noreply, socket}
  end

  @impl true
  def handle_info({event, _project}, socket)
      when event in [:project_added, :project_updated, :project_deleted] do
    projects = Projects.list_active()
    {:noreply, assign(socket, :projects, projects)}
  end

  @impl true
  def handle_info({:agent_output, lines}, socket) do
    output =
      (socket.assigns.agent_output ++ lines)
      |> Enum.take(-200)

    {:noreply, assign(socket, :agent_output, output)}
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
    {:noreply, assign(socket, :recipes, Ingredients.list_recipes())}
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
  def handle_event("file-search", %{"query" => query}, socket) do
    results = FileTree.search(query, socket.assigns.project_files)
    {:reply, %{files: results}, socket}
  end

  @impl true
  def handle_event("hotkey", %{"metaKey" => true}, socket), do: {:noreply, socket}
  def handle_event("hotkey", %{"ctrlKey" => true}, socket), do: {:noreply, socket}

  def handle_event("hotkey", %{"key" => key}, socket) do
    cond do
      socket.assigns.input_focused and key not in ["Escape"] ->
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
    Ingredients.force_refresh()
    {:noreply, socket}
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
           "Concocting started with #{socket.assigns.target_count} alchemists"
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
        {:noreply, put_flash(socket, :info, "Concocting stopped")}
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
            put_flash(socket, :info, "Alchemist count set to #{count}")
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
            put_flash(socket, :info, "Alchemist count set to #{count}")
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
  def handle_event("toggle-done-collapse", _params, socket) do
    {:noreply, assign(socket, :collapsed_done, !socket.assigns.collapsed_done)}
  end

  @impl true
  def handle_event("deselect-task", _params, socket) do
    {:noreply, push_patch(socket, to: project_path(socket))}
  end

  @impl true
  def handle_event("requeue-orphans", _params, socket) do
    active_ids = active_task_ids_from_agents(socket.assigns.agents)

    {:ok, count} = Ingredients.requeue_all_orphans(active_ids)
    {:noreply, put_flash(socket, :info, "Requeued #{count} orphaned task(s)")}
  end

  # Preview controls
  @impl true
  def handle_event("start-dev", %{"id" => wt_id}, socket) do
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

  # Project-level dev server controls
  @impl true
  def handle_event("start-project-dev", _params, socket) do
    project = socket.assigns.current_project

    if project do
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
  def handle_event("create-card-task", %{"concoction_id" => wt_id, "title" => title}, socket) do
    title = String.trim(title)

    if title != "" do
      case Ingredients.create_ingredient(%{title: title, concoction_id: wt_id, priority: 3}) do
        {:ok, item} when not is_nil(item) ->
          {:noreply, put_flash(socket, :info, "Ingredient added: #{item.id}")}

        _ ->
          {:noreply, put_flash(socket, :error, "Failed to add ingredient")}
      end
    else
      {:noreply, socket}
    end
  end

  # --- Task detail events ---

  @impl true
  def handle_event("claim", _params, socket) do
    case Ingredients.claim(socket.assigns.selected_task_id) do
      {:ok, _} ->
        {:noreply, put_flash(socket, :info, "Task claimed")}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Failed to claim: #{inspect(reason)}")}
    end
  end

  @impl true
  def handle_event("close", _params, socket) do
    case Ingredients.close(socket.assigns.selected_task_id) do
      {:ok, _} ->
        {:noreply, put_flash(socket, :info, "Task closed")}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Failed to close: #{inspect(reason)}")}
    end
  end

  @impl true
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
  def handle_event("confirm-merge", _params, socket) do
    case socket.assigns.pending_action do
      {:merge, task_id, pr_url} ->
        socket = assign(socket, :pending_action, nil)
        {:noreply, execute_merge(socket, task_id, pr_url)}

      {:direct_merge, task_id, git_path} ->
        socket = assign(socket, :pending_action, nil)
        {:noreply, execute_direct_merge(socket, task_id, git_path)}

      _ ->
        {:noreply, assign(socket, :pending_action, nil)}
    end
  end

  @impl true
  def handle_event("cancel-merge", _params, socket) do
    {:noreply, assign(socket, :pending_action, nil)}
  end

  @impl true
  def handle_event("direct-merge", _params, socket) do
    task = socket.assigns.selected_task

    cond do
      is_nil(task) || task.status != "brew_done" ->
        {:noreply, put_flash(socket, :error, "Concoction is not ready for merge")}

      is_nil(task.git_path) ->
        {:noreply, put_flash(socket, :error, "No git path found for this concoction")}

      true ->
        {:noreply, assign(socket, :pending_action, {:direct_merge, task.id, task.git_path})}
    end
  end

  @impl true
  def handle_event("promote-to-sampling", _params, socket) do
    task = socket.assigns.selected_task

    cond do
      is_nil(task) || task.status != "brew_done" ->
        {:noreply, put_flash(socket, :error, "Concoction is not ready for promotion")}

      true ->
        {:noreply, promote_to_sampling(socket, task)}
    end
  end

  @impl true
  def handle_event("requeue", _params, socket) do
    case Ingredients.unclaim(socket.assigns.selected_task_id) do
      {:ok, _} ->
        {:noreply, put_flash(socket, :info, "Task requeued")}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Failed to requeue: #{inspect(reason)}")}
    end
  end

  @impl true
  def handle_event("approve-merge-fix", _params, socket) do
    concoction_id = socket.assigns.selected_task_id

    # Unblock the fix-merge-conflicts ingredient(s) by setting them to "open"
    fix_ingredients =
      Ingredients.list_ingredients(concoction_id: concoction_id)
      |> Enum.filter(fn t ->
        t.status == "blocked" and String.contains?(t.title || "", "merge conflict")
      end)

    case fix_ingredients do
      [] ->
        {:noreply, put_flash(socket, :error, "No merge conflict ingredient found to approve")}

      ingredients ->
        for ingredient <- ingredients do
          Ingredients.update_ingredient(ingredient.id, %{status: "open"})
        end

        # Set concoction back to open so it gets dispatched
        Ingredients.update_concoction(concoction_id, %{status: "open"})

        {:noreply,
         put_flash(socket, :info, "Merge fix approved — concoction will be re-dispatched")}
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
        Ingredients.update_priority(id, new_priority)
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
      Ingredients.update_title(socket.assigns.selected_task_id, value)
    end

    {:noreply, assign(socket, :editing_field, nil)}
  end

  @impl true
  def handle_event("save-edit", %{"field" => "description", "value" => value}, socket) do
    Ingredients.update_description(socket.assigns.selected_task_id, String.trim(value))
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
          case Ingredients.get_ingredient(selected) do
            {:ok, task} -> task.concoction_id
            _ -> selected
          end
        end

      Ingredients.create_ingredient(%{title: title, concoction_id: worktree_id, priority: 3})
    end

    {:noreply, socket}
  end

  @impl true
  def handle_event("add-dep", %{"dep_id" => dep_id}, socket) do
    dep_id = String.trim(dep_id)

    if dep_id != "" do
      Ingredients.add_dependency(socket.assigns.selected_task_id, dep_id)
    end

    {:noreply, socket}
  end

  @impl true
  def handle_event("remove-dep", %{"blocker_id" => blocker_id}, socket) do
    Ingredients.remove_dependency(socket.assigns.selected_task_id, blocker_id)
    {:noreply, socket}
  end

  @impl true
  def handle_event("add-mcp", %{"mcp_name" => name, "mcp_url" => url}, socket) do
    name = String.trim(name)
    url = String.trim(url)

    if name != "" and url != "" do
      task_id = socket.assigns.selected_task_id

      existing =
        case Ingredients.get_concoction(task_id) do
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
      Ingredients.update_concoction(task_id, %{mcp_servers: updated})
    end

    {:noreply, socket}
  end

  @impl true
  def handle_event("remove-mcp", %{"name" => name}, socket) do
    task_id = socket.assigns.selected_task_id

    case Ingredients.get_concoction(task_id) do
      {:ok, wt} ->
        updated = Map.delete(wt.mcp_servers || %{}, name)
        mcp_servers = if updated == %{}, do: nil, else: updated
        Ingredients.update_concoction(task_id, %{mcp_servers: mcp_servers})

      _ ->
        :ok
    end

    {:noreply, socket}
  end

  # Context-sensitive primary input submit
  @impl true
  def handle_event("submit-input", %{"text" => text}, socket) do
    text = String.trim(text)

    cond do
      text == "" ->
        {:noreply, socket}

      is_nil(socket.assigns.selected_task_id) ->
        create_from_input(text, socket)

      socket.assigns.working_agent ->
        send_to_agent(text, socket)

      true ->
        create_child_from_input(text, socket)
    end
  end

  # --- Tab navigation ---

  @impl true
  def handle_event("switch-tab", %{"tab" => tab}, socket) do
    active_tab = String.to_existing_atom(tab)
    {:noreply, assign(socket, :active_tab, active_tab)}
  end

  # --- Project event handlers ---

  @impl true
  def handle_event("show-add-project", _params, socket) do
    {:noreply,
     assign(socket,
       show_add_project: true,
       add_project_error: nil,
       project_path_suggestions: []
     )}
  end

  @impl true
  def handle_event("cancel-add-project", _params, socket) do
    {:noreply,
     assign(socket,
       show_add_project: false,
       add_project_error: nil,
       project_path_suggestions: []
     )}
  end

  @impl true
  def handle_event("search-project-path", %{"path" => path}, socket) do
    suggestions = list_path_suggestions(path)
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
     })}
  end

  @impl true
  def handle_event("add-project", %{"path" => path}, socket) do
    path = String.trim(path)

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
               |> assign(projects: projects, show_add_project: false, add_project_error: nil)
               |> put_flash(:info, "Project added: #{project.name}")
               |> push_navigate(to: ~p"/projects/#{project.id}")}

            {:error, {:already_exists, existing}} ->
              {:noreply,
               socket
               |> assign(show_add_project: false, add_project_error: nil)
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
        Ingredients.update_recipe(socket.assigns.editing_recipe_id, attrs)
      else
        Ingredients.create_recipe(attrs)
      end

    case result do
      {:ok, _recipe} ->
        {:noreply,
         socket
         |> assign(:show_recipe_form, false)
         |> assign(:editing_recipe_id, nil)
         |> assign(:recipes, Ingredients.list_recipes())
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
    Ingredients.toggle_recipe(id)
    {:noreply, assign(socket, :recipes, Ingredients.list_recipes())}
  end

  @impl true
  def handle_event("edit-recipe", %{"id" => id}, socket) do
    case Ingredients.get_recipe(id) do
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
    Ingredients.delete_recipe(id)
    {:noreply, assign(socket, :recipes, Ingredients.list_recipes())}
  end

  defp parse_priority(nil), do: 3
  defp parse_priority(""), do: 3
  defp parse_priority(s) when is_binary(s), do: String.to_integer(s)
  defp parse_priority(n) when is_integer(n), do: n

  # --- Hotkey handlers ---

  defp handle_hotkey("?", socket), do: assign(socket, :show_help, !socket.assigns.show_help)

  defp handle_hotkey("Escape", socket) do
    cond do
      socket.assigns.pending_action ->
        socket
        |> assign(:pending_action, nil)
        |> clear_flash()

      socket.assigns.editing_field ->
        assign(socket, :editing_field, nil)

      socket.assigns.input_focused ->
        socket
        |> assign(:input_focused, false)
        |> push_event("blur-input", %{})

      socket.assigns.show_help ->
        assign(socket, :show_help, false)

      socket.assigns.selected_task_id ->
        push_patch(socket, to: project_path(socket))

      true ->
        socket
    end
  end

  defp handle_hotkey("j", socket) do
    max_idx = max(length(socket.assigns.card_ids) - 1, 0)
    idx = min(socket.assigns.selected_card + 1, max_idx)

    socket
    |> assign(:selected_card, idx)
    |> push_event("scroll-to-selected", %{})
  end

  defp handle_hotkey("k", socket) do
    idx = max(socket.assigns.selected_card - 1, 0)

    socket
    |> assign(:selected_card, idx)
    |> push_event("scroll-to-selected", %{})
  end

  defp handle_hotkey("g", socket), do: assign(socket, :selected_card, 0)

  defp handle_hotkey("G", socket) do
    max_idx = max(length(socket.assigns.card_ids) - 1, 0)
    assign(socket, :selected_card, max_idx)
  end

  defp handle_hotkey(key, socket) when key in ["Enter", "l"] do
    case Enum.at(socket.assigns.card_ids, socket.assigns.selected_card) do
      nil -> socket
      id -> push_patch(socket, to: project_path(socket) <> "?task=#{id}")
    end
  end

  defp handle_hotkey(key, socket) when key in ["Backspace", "h"] do
    if socket.assigns.selected_task_id do
      push_patch(socket, to: project_path(socket))
    else
      socket
    end
  end

  defp handle_hotkey("r", socket) do
    Ingredients.force_refresh()
    socket
  end

  defp handle_hotkey("s", socket) do
    case socket.assigns.current_project do
      nil ->
        put_flash(socket, :error, "Select a project first")

      project ->
        if socket.assigns.swarm_status == :running do
          Dispatcher.stop_swarm(project.id)
          put_flash(socket, :info, "Concocting stopped")
        else
          Dispatcher.start_swarm(project.id, socket.assigns.target_count)

          put_flash(
            socket,
            :info,
            "Concocting started with #{socket.assigns.target_count} alchemists"
          )
        end
    end
  end

  defp handle_hotkey(key, socket) when key in ["/", "c"] do
    push_event(socket, "focus-element", %{selector: "#primary-input"})
  end

  defp handle_hotkey(key, socket) when key in ["+", "="] do
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
          put_flash(socket, :info, "Alchemist count set to #{count}")
        else
          socket
        end
    end
  end

  defp handle_hotkey("-", socket) do
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
          put_flash(socket, :info, "Alchemist count set to #{count}")
        else
          socket
        end
    end
  end

  defp handle_hotkey("R", socket) do
    active_ids = active_task_ids_from_agents(socket.assigns.agents)

    {:ok, count} = Ingredients.requeue_all_orphans(active_ids)
    put_flash(socket, :info, "Requeued #{count} orphaned task(s)")
  end

  defp handle_hotkey("q", socket) do
    if socket.assigns.selected_task_id do
      case Ingredients.unclaim(socket.assigns.selected_task_id) do
        {:ok, _} ->
          put_flash(socket, :info, "Task requeued")

        {:error, reason} ->
          put_flash(socket, :error, "Failed to requeue: #{inspect(reason)}")
      end
    else
      socket
    end
  end

  defp handle_hotkey("x", socket) do
    if socket.assigns.selected_task_id do
      case Ingredients.close(socket.assigns.selected_task_id) do
        {:ok, _} ->
          put_flash(socket, :info, "Task closed")

        {:error, reason} ->
          put_flash(socket, :error, "Failed to close: #{inspect(reason)}")
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

  defp handle_hotkey("p", socket) do
    task = socket.assigns.selected_task

    if task && task.status == "brew_done" do
      promote_to_sampling(socket, task)
    else
      socket
    end
  end

  defp handle_hotkey("ArrowUp", socket) do
    if socket.assigns.selected_task_id do
      task = socket.assigns.selected_task
      current = (task && task.priority) || 3
      new_priority = max(current - 1, 0)

      if new_priority != current do
        Ingredients.update_priority(socket.assigns.selected_task_id, new_priority)
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
        Ingredients.update_priority(socket.assigns.selected_task_id, new_priority)
      end

      socket
    else
      socket
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

  # Lane jumps: 1=stockroom, 2=concocting, 3=sampling, 4=bottled
  defp handle_hotkey("1", socket), do: jump_to_lane(socket, ~w(ready blocked))
  defp handle_hotkey("2", socket), do: jump_to_lane(socket, ~w(running))
  defp handle_hotkey("3", socket), do: jump_to_lane(socket, ~w(pr))

  defp handle_hotkey("4", socket) do
    socket
    |> jump_to_lane(~w(done))
    |> assign(:collapsed_done, false)
  end

  # Tab switching: w=workbench, e=recipes, o=oracle
  defp handle_hotkey("w", socket), do: assign(socket, :active_tab, :workbench)
  defp handle_hotkey("e", socket), do: assign(socket, :active_tab, :recipes)
  defp handle_hotkey("o", socket), do: assign(socket, :active_tab, :oracle)

  defp handle_hotkey(_key, socket), do: socket

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
    project_dir = resolve_project_dir_for_concoction(task_id)

    case Git.merge_pr(project_dir, pr_url) do
      :ok ->
        Ingredients.add_note(task_id, "PR merged from dashboard: #{pr_url}")
        Ingredients.cleanup_merged_concoction(task_id)
        put_flash(socket, :info, "PR merged and worktree cleaned up")

      {:error, reason} ->
        put_flash(socket, :error, "Merge failed: #{inspect(reason)}")
    end
  end

  defp execute_direct_merge(socket, task_id, git_path) do
    project_dir = resolve_project_dir_for_concoction(task_id)
    task = socket.assigns.selected_task
    title = "[#{task_id}] #{(task && task.title) || task_id}"

    with {:ok, pr_url} <- Git.create_pr(project_dir, git_path, title),
         :ok <- Git.merge_pr(project_dir, pr_url) do
      Ingredients.add_note(
        task_id,
        "Direct merge from dashboard (PR created and merged): #{pr_url}"
      )

      Ingredients.update_concoction(task_id, %{pr_url: pr_url})
      Ingredients.cleanup_merged_concoction(task_id)
      put_flash(socket, :info, "PR created and merged: #{pr_url}")
    else
      {:error, reason} ->
        Ingredients.add_note(task_id, "Direct merge failed: #{inspect(reason)}")
        put_flash(socket, :error, "Direct merge failed: #{inspect(reason)}")
    end
  end

  # --- Promote brew_done to sampling (create PR) ---

  defp promote_to_sampling(socket, task) do
    task_id = task.id
    git_path = task.git_path
    project_dir = resolve_project_dir_for_concoction(task_id)

    if git_path do
      title = "[#{task_id}] #{task.title}"

      case Git.create_pr(project_dir, git_path, title) do
        {:ok, pr_url} ->
          Ingredients.add_note(task_id, "PR created from dashboard: #{pr_url}")

          Ingredients.update_concoction(task_id, %{
            status: "pr_open",
            pr_url: pr_url
          })

          put_flash(socket, :info, "PR created: #{pr_url}")

        {:error, reason} ->
          Ingredients.add_note(
            task_id,
            "PR creation failed: #{inspect(reason)}. Try again or create manually."
          )

          put_flash(socket, :error, "PR creation failed: #{inspect(reason)}")
      end
    else
      put_flash(socket, :error, "No git path found for this concoction")
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
    project_dir = resolve_project_dir_for_concoction(wt_id)

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

  defp create_from_input(text, socket) do
    # Detect question prefix: "? question text"
    if String.starts_with?(text, "?") do
      question_text = text |> String.trim_leading("?") |> String.trim()
      create_question(question_text, socket)
    else
      create_task_from_input(text, socket)
    end
  end

  defp create_question(text, socket) do
    project_id =
      if socket.assigns.current_project, do: socket.assigns.current_project.id, else: nil

    case Ingredients.create_concoction(%{
           title: text,
           kind: "question",
           priority: 2,
           project_id: project_id
         }) do
      {:ok, item} when not is_nil(item) ->
        {:noreply,
         socket
         |> assign(:active_tab, :oracle)
         |> put_flash(:info, "Question submitted")}

      {:ok, nil} ->
        {:noreply, put_flash(socket, :error, "Failed to submit question")}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Failed: #{inspect(reason)}")}
    end
  end

  defp create_task_from_input(text, socket) do
    {title, parent_id, dep_ids} = parse_smart_input(text)

    if parent_id do
      worktree_id =
        if String.starts_with?(to_string(parent_id), "wt-") do
          parent_id
        else
          case Ingredients.get_ingredient(parent_id) do
            {:ok, task} -> task.concoction_id || parent_id
            _ -> parent_id
          end
        end

      case Ingredients.create_ingredient(%{title: title, concoction_id: worktree_id, priority: 3}) do
        {:ok, item} when not is_nil(item) ->
          Enum.each(dep_ids, fn dep_id ->
            Ingredients.add_dependency(item.id, dep_id)
          end)

          {:noreply, put_flash(socket, :info, "Ingredient added: #{item.id}")}

        {:ok, nil} ->
          {:noreply, put_flash(socket, :error, "Failed to add ingredient")}

        {:error, reason} ->
          {:noreply, put_flash(socket, :error, "Failed: #{inspect(reason)}")}
      end
    else
      {concoction_title, description} = split_title_description(title)

      project_id =
        if socket.assigns.current_project, do: socket.assigns.current_project.id, else: nil

      case Ingredients.create_concoction(%{
             title: concoction_title,
             description: description,
             priority: 3,
             project_id: project_id
           }) do
        {:ok, item} when not is_nil(item) ->
          {:noreply, put_flash(socket, :info, "Concoction created: #{item.id}")}

        {:ok, nil} ->
          {:noreply, put_flash(socket, :error, "Failed to create concoction")}

        {:error, reason} ->
          {:noreply, put_flash(socket, :error, "Failed: #{inspect(reason)}")}
      end
    end
  end

  defp create_child_from_input(text, socket) do
    selected = socket.assigns.selected_task_id

    worktree_id =
      if String.starts_with?(to_string(selected), "wt-") do
        selected
      else
        case Ingredients.get_ingredient(selected) do
          {:ok, task} -> task.concoction_id || selected
          _ -> selected
        end
      end

    case Ingredients.create_ingredient(%{title: text, concoction_id: worktree_id, priority: 3}) do
      {:ok, item} when not is_nil(item) ->
        {:noreply,
         socket
         |> put_flash(:info, "Ingredient added: #{item.id}")
         |> push_patch(to: project_path(socket))}

      {:ok, nil} ->
        {:noreply, put_flash(socket, :error, "Failed to add ingredient")}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Failed: #{inspect(reason)}")}
    end
  end

  defp send_to_agent(text, socket) do
    agent = socket.assigns.working_agent

    if agent && agent.pid do
      Brewer.send_instruction(agent.pid, text)
      {:noreply, put_flash(socket, :info, "Sent to alchemist-#{agent.id}")}
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
    |> assign(:working_agent, nil)
    |> assign(:agent_output, [])
    |> assign(:page_title, "Dashboard")
  end

  defp select_task(socket, id) do
    old_agent = socket.assigns[:working_agent]
    if old_agent, do: Phoenix.PubSub.unsubscribe(@pubsub, "brewer:#{old_agent.id}")

    task =
      case Ingredients.show(id) do
        {:ok, task} -> task
        {:error, _} -> nil
      end

    {:ok, children} = Ingredients.children(id)

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

    socket
    |> assign(:selected_task_id, id)
    |> assign(:selected_task, task)
    |> assign(:children, children)
    |> assign(:editing_field, nil)
    |> assign(:working_agent, nil)
    |> assign(:agent_output, [])
    |> assign(:has_preview_config, has_preview)
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
      case Ingredients.show(id) do
        {:ok, task} -> task
        {:error, _} -> nil
      end

    {:ok, children} = Ingredients.children(id)

    socket
    |> assign(:selected_task, task)
    |> assign(:children, children)
  end

  defp find_working_agent(socket) do
    task_id = socket.assigns.selected_task_id

    agent =
      socket.assigns.agents
      |> Enum.find(fn a ->
        a.current_concoction && to_string(a.current_concoction.id) == to_string(task_id)
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

    # Hide cancelled concoctions (PR closed without merge)
    worktrees = Enum.reject(worktrees, &(&1.status == "cancelled"))

    tasks_by_wt =
      Enum.group_by(tasks, fn t ->
        t.concoction_id || t.parent
      end)

    agent_by_wt =
      agents
      |> Enum.filter(& &1.current_concoction)
      |> Map.new(fn a -> {to_string(a.current_concoction.id), a} end)

    active_wt_ids =
      agents
      |> Enum.flat_map(fn a ->
        if a.current_concoction, do: [to_string(a.current_concoction.id)], else: []
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
          wt.status in ["done", "closed", "merged"] -> "done"
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

  @doc false
  def parse_smart_input(input) do
    {input, parent_id} =
      case Regex.run(~r/#([a-z0-9]+-[a-z0-9]+)/, input) do
        [match, id] -> {String.replace(input, match, ""), id}
        _ -> {input, nil}
      end

    {input, dep_ids} =
      case Regex.scan(~r/>>([a-z0-9]+-[a-z0-9]+)/, input) do
        [] ->
          {input, []}

        matches ->
          dep_ids = Enum.map(matches, fn [_, id] -> id end)

          input =
            Enum.reduce(matches, input, fn [match, _], acc ->
              String.replace(acc, match, "")
            end)

          {input, dep_ids}
      end

    title = input |> String.replace(~r/\s+/, " ") |> String.trim()
    {title, parent_id, dep_ids}
  end

  # Splits free-text input into a short title (first line, max 80 chars) and
  # the rest as description. Single short lines return nil description.
  defp split_title_description(text) do
    lines = String.split(text, "\n", trim: false)
    first_line = String.trim(List.first(lines) || "")
    rest = lines |> Enum.drop(1) |> Enum.join("\n") |> String.trim()

    cond do
      rest != "" ->
        title =
          if String.length(first_line) > 80,
            do: String.slice(first_line, 0, 77) <> "...",
            else: first_line

        {title, rest}

      String.length(first_line) > 80 ->
        {String.slice(first_line, 0, 77) <> "...", first_line}

      true ->
        {first_line, nil}
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
      nil -> Ingredients.get_state()
      project -> Ingredients.get_state(project_id: project.id)
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
    # Get project's concoction IDs
    project_concoction_ids =
      state.tasks
      |> Enum.filter(fn item ->
        String.starts_with?(to_string(item.id), "wt-") and
          Map.get(item, :project_id) == project.id
      end)
      |> MapSet.new(& &1.id)

    tasks =
      Enum.filter(state.tasks, fn item ->
        if String.starts_with?(to_string(item.id), "wt-") do
          MapSet.member?(project_concoction_ids, item.id)
        else
          MapSet.member?(project_concoction_ids, item.concoction_id)
        end
      end)

    %{state | tasks: tasks}
  end

  defp resolve_project_dir_for_concoction(concoction_id) do
    case Ingredients.get_concoction(concoction_id) do
      {:ok, %{project_id: project_id}} when not is_nil(project_id) ->
        case Apothecary.Projects.get(project_id) do
          {:ok, project} -> project.path
          _ -> nil
        end

      _ ->
        nil
    end
  end

  defp entry_group(worktree, agents) do
    active_ids =
      agents
      |> Enum.flat_map(fn a ->
        if a.current_concoction, do: [to_string(a.current_concoction.id)], else: []
      end)
      |> MapSet.new()

    cond do
      MapSet.member?(active_ids, to_string(worktree.id)) -> "running"
      worktree.status == "brew_done" -> "running"
      worktree.status in ["open", "ready", "in_progress", "claimed", "revision_needed"] -> "ready"
      worktree.status in ["blocked", "merge_conflict"] -> "blocked"
      worktree.status == "pr_open" -> "pr"
      true -> "ready"
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

  defp build_card_ids(worktrees_by_status) do
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

    sampling =
      (worktrees_by_status["pr"] || []) |> sort_by_priority.()

    done =
      (worktrees_by_status["done"] || [])
      |> Enum.map(fn e -> e.worktree.id end)

    stockroom ++ brewing ++ sampling ++ done
  end

  defp rebuild_card_ids(socket, worktrees_by_status) do
    old_card_ids = socket.assigns.card_ids
    old_selected_id = Enum.at(old_card_ids, socket.assigns.selected_card)
    new_card_ids = build_card_ids(worktrees_by_status)

    idx =
      if old_selected_id do
        Enum.find_index(new_card_ids, &(&1 == old_selected_id)) ||
          min(socket.assigns.selected_card, max(length(new_card_ids) - 1, 0))
      else
        min(socket.assigns.selected_card, max(length(new_card_ids) - 1, 0))
      end

    socket
    |> assign(:card_ids, new_card_ids)
    |> assign(:selected_card, idx)
  end

  defp extract_ingredient_ids(tasks) do
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
      if Map.get(a, :current_concoction), do: [a.current_concoction.id], else: []
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
          nil -> %{status: :paused, target_count: 0, active_count: 0}
          ps -> ps
        end
    end
  end

  defp enrich_agents_with_pids(agents_map) do
    Enum.map(agents_map, fn {pid, agent_state} ->
      %{agent_state | pid: pid}
    end)
  end

  defp project_scoped_agents(agents, nil, _dispatcher_projects), do: agents

  defp project_scoped_agents(agents, project, dispatcher_projects) do
    case dispatcher_projects[project.id] do
      %{agents: project_agents} when is_map(project_agents) ->
        project_pids = MapSet.new(Map.keys(project_agents))
        Enum.filter(agents, fn a -> MapSet.member?(project_pids, a.pid) end)

      _ ->
        []
    end
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
      >
        <%!-- Top bar: branding + project selector + tabs --%>
        <div class="flex items-center gap-1 sm:gap-3 px-2 py-2 text-xs min-w-0">
          <.link
            navigate={~p"/"}
            class="font-apothecary text-sm font-bold tracking-wide text-base-content/80 shrink-0 hover:text-base-content transition-colors"
          >
            <span class="hidden sm:inline">Apothecary</span>
            <span class="sm:hidden">&#x2697;</span>
          </.link>
          <.project_selector
            projects={@projects}
            current_project={@current_project}
          />
          <div class="ml-auto flex items-center gap-1">
            <.tab_navigation :if={@current_project} active_tab={@active_tab} />
            <span
              class="text-base-content/30 cursor-pointer shrink-0 p-1 text-xs"
              phx-click="toggle-help"
            >
              ?
            </span>
          </div>
        </div>

        <div class="border-b border-base-content/10" />

        <%!-- Scrollable content --%>
        <div class="flex-1 overflow-y-auto">
          <%= if @active_tab == :oracle and @current_project do %>
            <div class="mx-auto px-2">
              <.oracle_view questions={@questions} agents={@agents} />
            </div>
          <% end %>
          <%= if @active_tab == :recipes and @current_project do %>
            <div class="mx-auto px-2">
              <.recipe_list
                recipes={@recipes}
                show_recipe_form={@show_recipe_form}
                recipe_form={@recipe_form}
                editing_recipe_id={@editing_recipe_id}
              />
            </div>
          <% end %>
          <%= if @active_tab == :workbench or is_nil(@current_project) do %>
            <div class="mx-auto px-2">
              <%!-- Primary input — centered, narrower --%>
              <div class="max-w-2xl mx-auto pt-3 sm:pt-6 pb-2 px-1 sm:px-0">
                <%= if @projects == [] and is_nil(@current_project) do %>
                  <div class="py-8 text-center">
                    <h2 class="text-base-content/50 text-lg font-semibold mb-3 font-apothecary">
                      No projects yet
                    </h2>
                    <p class="text-base-content/30 text-sm mb-4">
                      Open a git repository to get started.
                    </p>
                    <div class="flex gap-3">
                      <button
                        phx-click="show-add-project"
                        class="px-4 py-2 text-sm font-apothecary bg-primary/20 text-primary hover:bg-primary/30 rounded transition-colors cursor-pointer"
                      >
                        Open Project
                      </button>
                      <button
                        phx-click="show-new-project"
                        class="px-4 py-2 text-sm font-apothecary bg-base-content/10 text-base-content/50 hover:text-base-content/70 hover:bg-base-content/15 rounded transition-colors cursor-pointer"
                      >
                        New Project
                      </button>
                    </div>
                  </div>
                <% else %>
                  <%= if @projects != [] and is_nil(@current_project) do %>
                    <div class="py-8 text-center">
                      <h2 class="text-base-content/50 text-lg font-semibold mb-3 font-apothecary">
                        Select a project
                      </h2>
                      <p class="text-base-content/30 text-sm">
                        Choose a project above to see its workbench and concoctions.
                      </p>
                    </div>
                  <% else %>
                    <h2 class="text-base-content/50 text-lg font-semibold mb-2 font-apothecary">
                      Ready to mix?
                    </h2>
                    <%!-- Concoct + alchemist controls --%>
                    <% project_agents =
                      project_scoped_agents(@agents, @current_project, @dispatcher_projects) %>
                    <.concoct_controls
                      swarm_status={@swarm_status}
                      target_count={@target_count}
                      active_count={@active_count}
                      working_count={Enum.count(project_agents, &(&1.status == :working))}
                      auto_pr={@auto_pr}
                      gh_available={@gh_available}
                    />
                    <.primary_input input_focused={@input_focused} />
                    <div class="text-base-content/20 text-[10px] mt-1 px-1">
                      Start with <span class="text-primary/40">?</span> to ask about the codebase
                    </div>
                    <.activity_ticker agents={project_agents} />
                  <% end %>
                <% end %>
              </div>

              <%!-- Project preview --%>
              <div :if={@current_project} class="max-w-2xl mx-auto pb-2 px-1 sm:px-0">
                <.project_preview
                  project={@current_project}
                  dev_server={@dev_servers[@current_project.id]}
                  has_preview_config={@has_project_preview_config}
                />
              </div>

              <%= if @current_project do %>
                <%!-- Lane: STOCKROOM — ready + blocked --%>
                <% stockroom_entries =
                  Enum.flat_map(~w(ready blocked), fn g -> @worktrees_by_status[g] || [] end)
                  |> Enum.sort_by(fn e -> e.worktree.priority || 99 end) %>
                <div class="pb-2">
                  <div class="flex items-center gap-2 py-1.5">
                    <span class="uppercase text-xs tracking-wider font-bold text-emerald-400 font-apothecary">
                      STOCKROOM
                    </span>
                    <span class="text-base-content/30 text-xs">({length(stockroom_entries)})</span>
                    <span class="text-base-content/15 text-[10px] ml-1">1</span>
                  </div>
                  <%= if stockroom_entries != [] do %>
                    <div class="overflow-x-auto pb-2 scroll-smooth scroll-lane" id="stockroom-lane">
                      <div class="flex flex-nowrap gap-3 min-w-0">
                        <.worktree_card
                          :for={entry <- stockroom_entries}
                          worktree={entry.worktree}
                          tasks={entry.tasks}
                          agent={entry.agent}
                          dev_server={entry.dev_server}
                          selected={@selected_card_id == entry.worktree.id}
                          group={entry_group(entry.worktree, @agents)}
                        />
                      </div>
                    </div>
                  <% else %>
                    <div class="py-3 text-base-content/20 text-xs">empty</div>
                  <% end %>
                </div>

                <%!-- Lane: CONCOCTING — running --%>
                <% brewing_entries =
                  (@worktrees_by_status["running"] || [])
                  |> Enum.sort_by(fn e -> e.worktree.priority || 99 end) %>
                <div class="pb-2">
                  <div class="flex items-center gap-2 py-1.5">
                    <span class="uppercase text-xs tracking-wider font-bold text-amber-400 font-apothecary">
                      CONCOCTING
                    </span>
                    <span class="text-base-content/30 text-xs">({length(brewing_entries)})</span>
                    <span class="text-base-content/15 text-[10px] ml-1">2</span>
                  </div>
                  <%= if brewing_entries != [] do %>
                    <div class="overflow-x-auto pb-2 scroll-smooth scroll-lane" id="brewing-lane">
                      <div class="flex flex-nowrap gap-3 min-w-0">
                        <.worktree_card
                          :for={entry <- brewing_entries}
                          worktree={entry.worktree}
                          tasks={entry.tasks}
                          agent={entry.agent}
                          dev_server={entry.dev_server}
                          selected={@selected_card_id == entry.worktree.id}
                          group="running"
                        />
                      </div>
                    </div>
                  <% else %>
                    <div class="py-3 text-base-content/20 text-xs">empty</div>
                  <% end %>
                </div>

                <%!-- Lane: SAMPLING — pr --%>
                <% sampling_entries =
                  (@worktrees_by_status["pr"] || [])
                  |> Enum.sort_by(fn e -> e.worktree.priority || 99 end) %>
                <div class="pb-2">
                  <div class="flex items-center gap-2 py-1.5">
                    <span class="uppercase text-xs tracking-wider font-bold text-purple-400 font-apothecary">
                      SAMPLING
                    </span>
                    <span class="text-base-content/30 text-xs">({length(sampling_entries)})</span>
                    <span class="text-base-content/15 text-[10px] ml-1">3</span>
                  </div>
                  <%= if sampling_entries != [] do %>
                    <div class="overflow-x-auto pb-2 scroll-smooth scroll-lane" id="sampling-lane">
                      <div class="flex flex-nowrap gap-3 min-w-0">
                        <.worktree_card
                          :for={entry <- sampling_entries}
                          worktree={entry.worktree}
                          tasks={entry.tasks}
                          agent={entry.agent}
                          dev_server={entry.dev_server}
                          selected={@selected_card_id == entry.worktree.id}
                          group="pr"
                        />
                      </div>
                    </div>
                  <% else %>
                    <div class="py-3 text-base-content/20 text-xs">empty</div>
                  <% end %>
                </div>

                <%!-- BOTTLED — collapsible card grid --%>
                <% done_entries = @worktrees_by_status["done"] || [] %>
                <div class="pb-4">
                  <div class="flex items-center gap-2">
                    <.worktree_group_header
                      label="BOTTLED"
                      count={length(done_entries)}
                      color="text-green-400/70"
                      group="done"
                      collapsed={@collapsed_done}
                      collapsible={true}
                    />
                    <span class="text-base-content/15 text-[10px]">4</span>
                  </div>
                  <%= if done_entries != [] do %>
                    <div
                      :if={!@collapsed_done}
                      class="grid grid-cols-1 md:grid-cols-2 xl:grid-cols-3 gap-2 mt-1 mb-3"
                    >
                      <.worktree_card
                        :for={entry <- done_entries}
                        worktree={entry.worktree}
                        tasks={entry.tasks}
                        agent={entry.agent}
                        dev_server={entry.dev_server}
                        selected={@selected_card_id == entry.worktree.id}
                        group="done"
                      />
                    </div>
                  <% else %>
                    <div :if={!@collapsed_done} class="py-3 text-base-content/20 text-xs">empty</div>
                  <% end %>
                </div>
              <% end %>
            </div>
          <% end %>
        </div>

        <%!-- Footer --%>
        <div class="border-t border-base-content/10 px-2 py-1 text-xs flex items-center justify-between">
          <div class="flex items-center gap-3 text-base-content/30">
            <span class="hidden sm:inline">
              j/k:nav  1-4:lanes  enter:inspect  w/e/o:tabs  s:concoct
            </span>
            <span class="sm:hidden">tap card to inspect</span>
            <button
              :if={@orphan_count > 0}
              phx-click="requeue-orphans"
              class="text-amber-400 hover:text-amber-300 cursor-pointer"
            >
              {@orphan_count} orphan(s) [R]
            </button>
          </div>
          <div class="flex items-center gap-3 text-base-content/30">
            <Layouts.theme_toggle />
            <span class="cursor-pointer" phx-click="toggle-help">?:help</span>
          </div>
        </div>
      </div>

      <%!-- Detail drawer --%>
      <.task_detail_drawer
        :if={@selected_task && @selected_task_id}
        task={@selected_task}
        children={@children}
        editing_field={@editing_field}
        working_agent={@working_agent}
        agent_output={@agent_output}
        dev_server={@dev_servers[@selected_task_id]}
        has_preview_config={@has_preview_config}
        pending_action={@pending_action}
      />

      <.which_key_overlay
        :if={@show_help}
        page={:dashboard}
        has_selected_task={@selected_task_id != nil}
      />

      <.diff_overlay :if={@diff_view} diff_view={@diff_view} />

      <.add_project_modal
        :if={@show_add_project}
        error={@add_project_error}
        suggestions={@project_path_suggestions}
      />

      <.new_project_modal
        :if={@show_new_project}
        error={@new_project_error}
        progress={@bootstrap_progress}
      />
    </Layouts.app>
    """
  end
end
