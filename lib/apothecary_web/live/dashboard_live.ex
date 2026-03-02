defmodule ApothecaryWeb.DashboardLive do
  use ApothecaryWeb, :live_view

  alias Apothecary.{Brewer, DevServer, DiffParser, Git, Ingredients, Dispatcher}

  @pubsub Apothecary.PubSub

  @group_order ~w(running ready blocked pr done)


  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      Ingredients.subscribe()
      Dispatcher.subscribe()
      DevServer.subscribe()
    end

    task_state = Ingredients.get_state()
    dispatcher_status = Dispatcher.status()
    agents = enrich_agents_with_pids(dispatcher_status.agents)
    active_task_ids = active_task_ids(dispatcher_status)
    dev_servers = DevServer.list_servers()

    if connected?(socket) do
      subscribe_to_agents(agents)
    end

    worktrees_by_status = build_worktree_groups(task_state.tasks, agents, dev_servers)

    socket =
      socket
      |> assign(:page_title, "Dashboard")
      |> assign(:stats, task_state.stats)
      |> assign(:ready_tasks, task_state.ready_tasks)
      |> assign(:last_poll, task_state.last_poll)
      |> assign(:error, task_state.error)
      |> assign(:task_count, length(task_state.tasks))
      |> assign(:swarm_status, dispatcher_status.status)
      |> assign(:target_count, max(dispatcher_status.target_count, 1))
      |> assign(:active_count, dispatcher_status.active_count)
      |> assign(:agents, agents)
      |> assign(:show_help, false)
      |> assign(:input_focused, false)
      |> assign(:orphan_count, compute_orphan_count(task_state.tasks, active_task_ids))
      |> assign(:dev_servers, dev_servers)
      |> assign(:worktrees_by_status, worktrees_by_status)
      |> assign(:collapsed_done, true)
      |> assign(:card_ids, build_card_ids(worktrees_by_status))
      |> assign(:selected_card, 0)
      # Panel state
      |> assign(:selected_task_id, nil)
      |> assign(:selected_task, nil)
      |> assign(:children, [])
      |> assign(:editing_field, nil)
      |> assign(:working_agent, nil)
      |> assign(:agent_output, [])
      |> assign(:diff_view, nil)
      |> assign(:known_ingredient_ids, extract_ingredient_ids(task_state.tasks))

    {:ok, socket}
  end

  @impl true
  def handle_params(%{"id" => id}, _uri, socket) do
    {:noreply, select_task(socket, id)}
  end

  def handle_params(%{"task" => id}, _uri, socket) do
    {:noreply, select_task(socket, id)}
  end

  def handle_params(_params, _uri, socket) do
    {:noreply, select_task(socket, nil)}
  end

  # --- PubSub handlers ---

  @impl true
  def handle_info({:ingredients_update, state}, socket) do
    new_ids = extract_ingredient_ids(state.tasks)
    old_ids = socket.assigns.known_ingredient_ids
    created = MapSet.difference(new_ids, old_ids)

    socket =
      if MapSet.size(created) > 0 do
        new_ingredients = Enum.filter(state.tasks, &MapSet.member?(created, &1.id))
        names = Enum.map_join(new_ingredients, ", ", & &1.title)
        put_flash(socket, :info, "Ingredient discovered: #{names}")
      else
        socket
      end

    agents = socket.assigns.agents
    active_task_ids = active_task_ids_from_agents(agents)
    worktrees_by_status = build_worktree_groups(state.tasks, agents, socket.assigns.dev_servers)

    socket =
      socket
      |> assign(:stats, state.stats)
      |> assign(:ready_tasks, state.ready_tasks)
      |> assign(:last_poll, state.last_poll)
      |> assign(:error, state.error)
      |> assign(:task_count, length(state.tasks))
      |> assign(:orphan_count, compute_orphan_count(state.tasks, active_task_ids))
      |> assign(:worktrees_by_status, worktrees_by_status)
      |> assign(:card_ids, build_card_ids(worktrees_by_status))
      |> assign(:known_ingredient_ids, new_ids)
      |> clamp_card_index()

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

    socket =
      socket
      |> assign(:swarm_status, status.status)
      |> assign(:target_count, status.target_count)
      |> assign(:active_count, status.active_count)
      |> assign(:agents, agents)

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
    task_state = Ingredients.get_state()
    agents = socket.assigns.agents
    worktrees_by_status = build_worktree_groups(task_state.tasks, agents, dev_servers)

    socket =
      socket
      |> assign(:dev_servers, dev_servers)
      |> assign(:worktrees_by_status, worktrees_by_status)
      |> assign(:card_ids, build_card_ids(worktrees_by_status))
      |> clamp_card_index()

    {:noreply, socket}
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
        %{files: [], selected_file: 0, worktree_id: worktree_id, loading: false, error: "No changes found"}
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

  # --- Event handlers ---

  @impl true
  def handle_event("input-focus", _params, socket),
    do: {:noreply, assign(socket, :input_focused, true)}

  @impl true
  def handle_event("input-blur", _params, socket),
    do: {:noreply, assign(socket, :input_focused, false)}

  @impl true
  def handle_event("hotkey", %{"key" => key}, socket) do
    cond do
      socket.assigns.input_focused and key not in ["Escape", "Enter"] ->
        {:noreply, socket}

      socket.assigns.diff_view != nil ->
        {:noreply, handle_diff_hotkey(key, socket)}

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
    Dispatcher.start_swarm(socket.assigns.target_count)

    {:noreply,
     put_flash(socket, :info, "Brewing started with #{socket.assigns.target_count} brewers")}
  end

  @impl true
  def handle_event("stop-swarm", _params, socket) do
    Dispatcher.stop_swarm()
    {:noreply, put_flash(socket, :info, "Brewing stopped")}
  end

  @impl true
  def handle_event("inc-agents", _params, socket) do
    count = min(socket.assigns.target_count + 1, 10)

    if socket.assigns.swarm_status == :running do
      Dispatcher.set_agent_count(count)
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

  @impl true
  def handle_event("dec-agents", _params, socket) do
    count = max(socket.assigns.target_count - 1, 1)

    if socket.assigns.swarm_status == :running do
      Dispatcher.set_agent_count(count)
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

  @impl true
  def handle_event("toggle-done-collapse", _params, socket) do
    {:noreply, assign(socket, :collapsed_done, !socket.assigns.collapsed_done)}
  end

  @impl true
  def handle_event("deselect-task", _params, socket) do
    {:noreply, push_patch(socket, to: ~p"/")}
  end

  @impl true
  def handle_event("requeue-orphans", _params, socket) do
    active_ids = active_task_ids_from_agents(socket.assigns.agents)

    {:ok, count} = Ingredients.requeue_all_orphans(active_ids)
    {:noreply, put_flash(socket, :info, "Requeued #{count} orphaned task(s)")}
  end

  # Dev server controls
  @impl true
  def handle_event("start-dev", %{"id" => wt_id}, socket) do
    case DevServer.start_server(wt_id) do
      {:ok, _base_port} ->
        {:noreply, put_flash(socket, :info, "Dev server starting for #{wt_id}")}

      {:error, :no_dev_config} ->
        {:noreply, put_flash(socket, :error, "No .apothecary/dev.yaml found in worktree")}

      {:error, :already_running} ->
        {:noreply, put_flash(socket, :info, "Dev server already running")}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Failed to start dev: #{inspect(reason)}")}
    end
  end

  @impl true
  def handle_event("stop-dev", %{"id" => wt_id}, socket) do
    DevServer.stop_server(wt_id)
    {:noreply, put_flash(socket, :info, "Dev server stopped for #{wt_id}")}
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
        case Apothecary.Git.merge_pr(pr_url) do
          :ok ->
            Ingredients.add_note(task.id, "PR merged from dashboard: #{pr_url}")
            Ingredients.cleanup_merged_concoction(task.id)
            {:noreply, put_flash(socket, :info, "PR merged and worktree cleaned up")}

          {:error, reason} ->
            {:noreply, put_flash(socket, :error, "Merge failed: #{inspect(reason)}")}
        end
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

  # --- Hotkey handlers ---

  defp handle_hotkey("?", socket), do: assign(socket, :show_help, !socket.assigns.show_help)

  defp handle_hotkey("Escape", socket) do
    cond do
      socket.assigns.editing_field ->
        assign(socket, :editing_field, nil)

      socket.assigns.input_focused ->
        socket
        |> assign(:input_focused, false)
        |> push_event("blur-input", %{})

      socket.assigns.show_help ->
        assign(socket, :show_help, false)

      socket.assigns.selected_task_id ->
        push_patch(socket, to: ~p"/")

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
      id -> push_patch(socket, to: ~p"/?task=#{id}")
    end
  end

  defp handle_hotkey(key, socket) when key in ["Backspace", "h"] do
    if socket.assigns.selected_task_id do
      push_patch(socket, to: ~p"/")
    else
      socket
    end
  end

  defp handle_hotkey("r", socket) do
    Ingredients.force_refresh()
    socket
  end

  defp handle_hotkey("s", socket) do
    if socket.assigns.swarm_status == :running do
      Dispatcher.stop_swarm()
      put_flash(socket, :info, "Brewing stopped")
    else
      Dispatcher.start_swarm(socket.assigns.target_count)
      put_flash(socket, :info, "Brewing started with #{socket.assigns.target_count} brewers")
    end
  end

  defp handle_hotkey(key, socket) when key in ["/", "c"] do
    push_event(socket, "focus-element", %{selector: "#primary-input"})
  end

  defp handle_hotkey(key, socket) when key in ["+", "="] do
    count = min(socket.assigns.target_count + 1, 10)

    if socket.assigns.swarm_status == :running do
      Dispatcher.set_agent_count(count)
    end

    socket = assign(socket, :target_count, count)

    if socket.assigns.swarm_status != :running do
      put_flash(socket, :info, "Brewer count set to #{count}")
    else
      socket
    end
  end

  defp handle_hotkey("-", socket) do
    count = max(socket.assigns.target_count - 1, 1)

    if socket.assigns.swarm_status == :running do
      Dispatcher.set_agent_count(count)
    end

    socket = assign(socket, :target_count, count)

    if socket.assigns.swarm_status != :running do
      put_flash(socket, :info, "Brewer count set to #{count}")
    else
      socket
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

    if task && Map.get(task, :pr_url) && task.status == "pr_open" do
      case Apothecary.Git.merge_pr(task.pr_url) do
        :ok ->
          Ingredients.add_note(task.id, "PR merged from dashboard: #{task.pr_url}")
          Ingredients.cleanup_merged_concoction(task.id)
          put_flash(socket, :info, "PR merged and worktree cleaned up")

        {:error, reason} ->
          put_flash(socket, :error, "Merge failed: #{inspect(reason)}")
      end
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
          put_flash(socket, :info, "Stopping dev server for #{wt.id}")
        else
          case DevServer.start_server(wt.id) do
            {:ok, _} -> put_flash(socket, :info, "Starting dev server for #{wt.id}")
            {:error, :no_dev_config} -> put_flash(socket, :error, "No .apothecary/dev.yaml")
            {:error, reason} -> put_flash(socket, :error, "Dev error: #{inspect(reason)}")
          end
        end
    end
  end

  # Lane jumps: 1=stockroom, 2=brewing, 3=assaying, 4=bottled
  defp handle_hotkey("1", socket), do: jump_to_lane(socket, ~w(ready blocked))
  defp handle_hotkey("2", socket), do: jump_to_lane(socket, ~w(running))
  defp handle_hotkey("3", socket), do: jump_to_lane(socket, ~w(pr))

  defp handle_hotkey("4", socket) do
    socket
    |> jump_to_lane(~w(done))
    |> assign(:collapsed_done, false)
  end

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

    diff_view = %{
      files: [],
      selected_file: 0,
      worktree_id: wt_id,
      loading: true,
      error: nil
    }

    Elixir.Task.start(fn ->
      result =
        cond do
          pr_url && pr_url != "" -> Git.pr_diff(pr_url)
          git_path && git_path != "" -> Git.worktree_diff(git_path)
          true -> {:error, "No PR URL or git path on this worktree"}
        end

      send(lv, {:diff_result, wt_id, result})
    end)

    assign(socket, :diff_view, diff_view)
  end

  # --- Input handlers ---

  defp create_from_input(text, socket) do
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
      case Ingredients.create_concoction(%{title: title, priority: 3}) do
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
         |> push_patch(to: ~p"/")}

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
      {:noreply, put_flash(socket, :info, "Sent to brewer-#{agent.id}")}
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

    socket
    |> assign(:selected_task_id, id)
    |> assign(:selected_task, task)
    |> assign(:children, children)
    |> assign(:editing_field, nil)
    |> assign(:working_agent, nil)
    |> assign(:agent_output, [])
    |> assign(:page_title, "Task #{id}")
    |> find_working_agent()
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
          wt.status in ["open", "ready"] -> "ready"
          wt.status in ["in_progress", "claimed"] -> "ready"
          wt.status == "blocked" -> "blocked"
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

  defp entry_group(worktree, agents) do
    active_ids =
      agents
      |> Enum.flat_map(fn a -> if a.current_concoction, do: [to_string(a.current_concoction.id)], else: [] end)
      |> MapSet.new()

    cond do
      MapSet.member?(active_ids, to_string(worktree.id)) -> "running"
      worktree.status in ["open", "ready", "in_progress", "claimed", "revision_needed"] -> "ready"
      worktree.status == "blocked" -> "blocked"
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
      nil -> socket
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

    assaying =
      (worktrees_by_status["pr"] || []) |> sort_by_priority.()

    done =
      (worktrees_by_status["done"] || [])
      |> Enum.map(fn e -> e.worktree.id end)

    stockroom ++ brewing ++ assaying ++ done
  end

  defp clamp_card_index(socket) do
    max_idx = max(length(socket.assigns.card_ids) - 1, 0)
    idx = min(socket.assigns.selected_card, max_idx)
    assign(socket, :selected_card, idx)
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

  defp active_task_ids(dispatcher_status) do
    dispatcher_status.agents
    |> Map.values()
    |> Enum.flat_map(fn a ->
      if a.current_concoction, do: [a.current_concoction.id], else: []
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

  defp enrich_agents_with_pids(agents_map) do
    Enum.map(agents_map, fn {pid, agent_state} ->
      %{agent_state | pid: pid}
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
      >
        <%!-- Status controls bar --%>
        <div class="w-full max-w-5xl mx-auto">
          <.status_controls
            swarm_status={@swarm_status}
            target_count={@target_count}
            active_count={@active_count}
            working_count={Enum.count(@agents, &(&1.status == :working))}
          />
        </div>

        <div class="border-b border-base-content/10" />

        <%!-- Scrollable content --%>
        <div class="flex-1 overflow-y-auto">
          <div class="max-w-5xl mx-auto px-6">
            <%!-- Primary input — centered, narrower --%>
            <div class="max-w-2xl mx-auto pt-40 pb-4">
              <h2 class="text-base-content/50 text-lg font-semibold mb-4 font-apothecary">What shall we concoct?</h2>
              <.primary_input input_focused={@input_focused} />
              <.activity_ticker agents={@agents} />
            </div>

            <%!-- Lane: STOCKROOM — ready + blocked --%>
            <% stockroom_entries =
              Enum.flat_map(~w(ready blocked), fn g -> @worktrees_by_status[g] || [] end)
              |> Enum.sort_by(fn e -> e.worktree.priority || 99 end)
            %>
            <div class="pb-2">
              <div class="flex items-center gap-2 py-1.5">
                <span class="uppercase text-xs tracking-wider font-bold text-emerald-400 font-apothecary">STOCKROOM</span>
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

            <%!-- Lane: BREWING — running --%>
            <% brewing_entries =
              (@worktrees_by_status["running"] || [])
              |> Enum.sort_by(fn e -> e.worktree.priority || 99 end)
            %>
            <div class="pb-2">
              <div class="flex items-center gap-2 py-1.5">
                <span class="uppercase text-xs tracking-wider font-bold text-amber-400 font-apothecary">BREWING</span>
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

            <%!-- Lane: ASSAYING — pr --%>
            <% assaying_entries =
              (@worktrees_by_status["pr"] || [])
              |> Enum.sort_by(fn e -> e.worktree.priority || 99 end)
            %>
            <div class="pb-2">
              <div class="flex items-center gap-2 py-1.5">
                <span class="uppercase text-xs tracking-wider font-bold text-purple-400 font-apothecary">ASSAYING</span>
                <span class="text-base-content/30 text-xs">({length(assaying_entries)})</span>
                <span class="text-base-content/15 text-[10px] ml-1">3</span>
              </div>
              <%= if assaying_entries != [] do %>
                <div class="overflow-x-auto pb-2 scroll-smooth scroll-lane" id="assaying-lane">
                  <div class="flex flex-nowrap gap-3 min-w-0">
                    <.worktree_card
                      :for={entry <- assaying_entries}
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
                <.worktree_group_header label="BOTTLED" count={length(done_entries)} color="text-green-400/70" group="done" collapsed={@collapsed_done} collapsible={true} />
                <span class="text-base-content/15 text-[10px]">4</span>
              </div>
              <%= if done_entries != [] do %>
                <div :if={!@collapsed_done} class="grid grid-cols-1 md:grid-cols-2 xl:grid-cols-3 gap-2 mt-1 mb-3">
                  <.worktree_card :for={entry <- done_entries} worktree={entry.worktree} tasks={entry.tasks} agent={entry.agent} dev_server={entry.dev_server} selected={@selected_card_id == entry.worktree.id} group="done" />
                </div>
              <% else %>
                <div :if={!@collapsed_done} class="py-3 text-base-content/20 text-xs">empty</div>
              <% end %>
            </div>
          </div>
        </div>

        <%!-- Footer --%>
        <div class="border-t border-base-content/10 px-6 py-1 text-xs flex items-center justify-between">
          <div class="flex items-center gap-3">
            <span class="text-base-content/30">j/k:nav  1-4:lanes  enter:inspect</span>
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
      />

      <.which_key_overlay
        :if={@show_help}
        page={:dashboard}
        has_selected_task={@selected_task_id != nil}
      />

      <.diff_overlay :if={@diff_view} diff_view={@diff_view} />
    </Layouts.app>
    """
  end
end
