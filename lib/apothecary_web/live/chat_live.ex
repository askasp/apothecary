defmodule ApothecaryWeb.ChatLive do
  use ApothecaryWeb, :live_view

  alias Apothecary.{Worktrees, Dispatcher, Projects}

  alias ApothecaryWeb.ChatLive.{
    ChatMessage,
    CommandHandler,
    CommandParser,
    Context
  }

  import ApothecaryWeb.ChatComponents

  @pubsub Apothecary.PubSub
  @max_messages 500

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      Worktrees.subscribe()
      Dispatcher.subscribe()
      Projects.subscribe()
    end

    dispatcher_status = Dispatcher.status()
    agents = agents_to_list(dispatcher_status.agents)
    projects = Projects.list_active()

    if connected?(socket) do
      subscribe_to_agents(agents)
    end

    # Default to first project (most recently active)
    default_project = List.first(projects)

    worktrees_state =
      if default_project do
        Worktrees.get_state(project_id: default_project.id)
      else
        %{tasks: [], ready_tasks: [], stats: %{}, error: nil}
      end

    socket =
      socket
      |> assign(:page_title, "Chat")
      |> assign(:messages, [])
      |> assign(:msg_counter, 0)
      |> assign(:context, Context.initial())
      |> assign(:context_stack, [])
      |> assign(:current_project, default_project)
      |> assign(:projects, projects)
      |> assign(:worktrees_state, worktrees_state)
      |> assign(:agents, agents)
      |> assign(:input_value, "")
      |> assign(:log_streaming, MapSet.new())
      |> assign(:show_project_switcher, false)
      |> assign(:switcher_selected, 0)
      |> assign(:switcher_query, "")
      |> assign(:dispatcher_projects, dispatcher_status[:projects] || %{})
      |> assign(:path_suggestions, [])
      |> assign(:path_suggestion_selected, 0)
      |> assign(:path_command_prefix, "add")

    {:ok, socket}
  end

  @impl true
  def handle_params(%{"project_id" => project_id}, _uri, socket) do
    {:noreply, apply_project(socket, project_id)}
  end

  def handle_params(_params, _uri, socket) do
    {:noreply, socket}
  end

  # ── Render ──────────────────────────────────────────────

  @impl true
  def render(assigns) do
    ~H"""
    <div id="chat-root" class="chat-container" phx-hook="ChatKeys">
      <.chat_top_bar
        current_project={@current_project}
        projects={@projects}
        show_project_switcher={@show_project_switcher}
        switcher_selected={@switcher_selected}
        switcher_query={@switcher_query}
        worktrees_state={@worktrees_state}
        agents={@agents}
        dispatcher_projects={@dispatcher_projects}
      />
      <div id="chat-log" class="chat-log" phx-hook="ChatScroll">
        <.chat_welcome :if={@messages == []} has_project={@current_project != nil} />
        <%= for msg <- @messages do %>
          <%= if msg.type in [:live_status, :live_info] do %>
            <.chat_message
              msg={msg}
              worktrees_state={@worktrees_state}
              agents={@agents}
              current_project={@current_project}
              dispatcher_projects={@dispatcher_projects}
            />
          <% else %>
            <.chat_message msg={msg} />
          <% end %>
        <% end %>
      </div>

      <.chat_input
        context={@context}
        context_stack={@context_stack}
        input_value={@input_value}
        path_suggestions={@path_suggestions}
        path_suggestion_selected={@path_suggestion_selected}
        current_project={@current_project}
      />
    </div>
    """
  end

  # ── Events ─────────────────────────────────────────────

  @impl true
  def handle_event("restore-messages", %{"messages" => messages}, socket) when is_list(messages) do
    restored =
      messages
      |> Enum.map(fn m ->
        %ChatMessage{
          id: m["id"] || 0,
          type: String.to_existing_atom(m["type"] || "system"),
          source: m["source"] || "apothecary",
          context_label: m["context_label"] || "",
          body: m["body"] || "",
          timestamp:
            case DateTime.from_iso8601(m["timestamp"] || "") do
              {:ok, dt, _} -> dt
              _ -> DateTime.utc_now()
            end
        }
      end)

    max_id = restored |> Enum.map(& &1.id) |> Enum.max(fn -> 0 end)

    {:noreply,
     socket
     |> assign(:messages, restored)
     |> assign(:msg_counter, max_id + 1)}
  end

  def handle_event("restore-messages", _params, socket), do: {:noreply, socket}

  def handle_event("submit", %{"text" => text}, socket) do
    text = String.trim(text)

    if text == "" do
      {:noreply, socket}
    else
      context = socket.assigns.context
      parsed = CommandParser.parse(text, context)
      {messages, updates} = CommandHandler.execute(parsed, socket)

      socket =
        socket
        |> append_messages(messages)
        |> apply_updates(updates)
        |> assign(:input_value, "")

      {:noreply, socket}
    end
  end

  def handle_event("toggle-project-switcher", _params, socket) do
    {:noreply, assign(socket, :show_project_switcher, !socket.assigns.show_project_switcher)}
  end

  def handle_event("select-project", %{"id" => project_id}, socket) do
    socket =
      socket
      |> apply_project(project_id)
      |> assign(:show_project_switcher, false)
      |> assign(:switcher_query, "")
      |> assign(:switcher_selected, 0)

    {:noreply, socket}
  end

  def handle_event("switcher-search", %{"value" => query}, socket) do
    {:noreply, assign(socket, switcher_query: query, switcher_selected: 0)}
  end

  def handle_event("switcher-key", %{"key" => key}, socket) do
    filtered = filter_projects(socket.assigns.projects, socket.assigns.switcher_query)
    max_idx = max(length(filtered) - 1, 0)
    sel = socket.assigns.switcher_selected

    case key do
      "ArrowDown" ->
        {:noreply, assign(socket, :switcher_selected, min(sel + 1, max_idx))}

      "ArrowUp" ->
        {:noreply, assign(socket, :switcher_selected, max(sel - 1, 0))}

      "Enter" ->
        project = Enum.at(filtered, sel)

        if project do
          socket =
            socket
            |> apply_project(project.id)
            |> assign(:show_project_switcher, false)
            |> assign(:switcher_query, "")
            |> assign(:switcher_selected, 0)

          {:noreply, socket}
        else
          {:noreply, socket}
        end

      "Escape" ->
        {:noreply,
         assign(socket,
           show_project_switcher: false,
           switcher_query: "",
           switcher_selected: 0
         )}

      _ ->
        {:noreply, socket}
    end
  end

  def handle_event("input-change", %{"value" => value}, socket) do
    cond do
      # Path autocomplete: "add /path", "/add /path", "new /path", "/new /path"
      match = Regex.run(~r{^/?(add|new)\s+([~/]\S*)$}, value) ->
        [_, prefix, p] = match
        suggestions = list_path_suggestions(expand_tilde(p))
        {:noreply, assign(socket, path_suggestions: suggestions, path_suggestion_selected: 0, path_command_prefix: prefix)}

      # Path autocomplete: "p add /path", "/p add /path"
      match = Regex.run(~r{^/?p(?:roject)?\s+add\s+([~/]\S*)$}, value) ->
        [_, p] = match
        suggestions = list_path_suggestions(expand_tilde(p))
        {:noreply, assign(socket, path_suggestions: suggestions, path_suggestion_selected: 0, path_command_prefix: "add")}

      # Path autocomplete: "p /path", "/p /path" (switch by path)
      match = Regex.run(~r{^/?(p(?:roject)?)\s+([~/]\S*)$}, value) ->
        [_, prefix, p] = match
        suggestions = list_path_suggestions(expand_tilde(p))
        {:noreply, assign(socket, path_suggestions: suggestions, path_suggestion_selected: 0, path_command_prefix: prefix)}

      # Project name autocomplete: "p name" or "/p name" without a path char
      match = Regex.run(~r{^/?(p(?:roject)?)\s+([^~/].*)$}, value) ->
        [_, prefix, query] = match
        suggestions = list_project_suggestions(socket.assigns.projects, String.trim(query))
        {:noreply, assign(socket, path_suggestions: suggestions, path_suggestion_selected: 0, path_command_prefix: prefix)}

      # Worktree ID autocomplete for all wt-targeting commands (slash and bare)
      match = Regex.run(~r{^(/(?:wt|info|diff|tasks|log|close|merge|pr|preview|mcp)|(?:wt|info|diff|tasks|log|close|merge|pr|preview|mcp|[idtlcm]))\s+(.*)$}, value) ->
        [_, prefix, query] = match
        suggestions = list_worktree_suggestions(socket.assigns.worktrees_state, String.trim(query))
        {:noreply, assign(socket, path_suggestions: suggestions, path_suggestion_selected: 0, path_command_prefix: String.trim_leading(prefix, "/"))}

      # Clear suggestions
      socket.assigns.path_suggestions != [] ->
        {:noreply, assign(socket, path_suggestions: [], path_suggestion_selected: 0)}

      true ->
        {:noreply, socket}
    end
  end

  def handle_event("select-path", %{"path" => path}, socket) do
    prefix = socket.assigns.path_command_prefix

    wt_prefixes = ~w(wt info diff tasks log close merge pr preview mcp i d t l c m)

    cond do
      # Worktree selection — execute the command with the selected wt id
      prefix in wt_prefixes ->
        parsed = CommandParser.parse("/#{prefix} #{path}", socket.assigns.context)
        {messages, updates} = CommandHandler.execute(parsed, socket)

        socket =
          socket
          |> append_messages(messages)
          |> apply_updates(updates)
          |> assign(path_suggestions: [], path_suggestion_selected: 0, input_value: "")
          |> push_event("clear-input", %{})

        {:noreply, socket}

      # Project name selection — switch to project
      prefix in ["p", "/p", "project", "/project"] && !String.starts_with?(path, "/") && !String.starts_with?(path, "~") ->
        parsed = CommandParser.parse("p #{path}", socket.assigns.context)
        {messages, updates} = CommandHandler.execute(parsed, socket)

        socket =
          socket
          |> append_messages(messages)
          |> apply_updates(updates)
          |> assign(path_suggestions: [], path_suggestion_selected: 0, input_value: "")
          |> push_event("clear-input", %{})

        {:noreply, socket}

      # Filesystem path — git repo, add as project
      File.dir?(Path.join(path, ".git")) ->
        case Projects.add(path) do
          {:ok, project} ->
            projects = Projects.list_active()
            state = Worktrees.get_state(project_id: project.id)
            c = socket.assigns.msg_counter
            msg = ChatMessage.system(c, "project → #{project.name}")

            socket =
              socket
              |> assign(
                current_project: project,
                projects: projects,
                worktrees_state: state,
                path_suggestions: [],
                path_suggestion_selected: 0,
                input_value: ""
              )
              |> append_message(msg)
              |> update_counter()
              |> push_event("clear-input", %{})

            {:noreply, socket}

          {:error, _reason} ->
            case Projects.get_by_path(path) do
              {:ok, project} ->
                socket =
                  socket
                  |> apply_project(project.id)
                  |> assign(path_suggestions: [], path_suggestion_selected: 0, input_value: "")
                  |> push_event("clear-input", %{})

                {:noreply, socket}

              _ ->
                c = socket.assigns.msg_counter
                msg = ChatMessage.error(c, "failed to add project")
                socket = socket |> append_message(msg) |> update_counter() |> assign(path_suggestions: [], input_value: "")
                {:noreply, socket}
            end
        end

      # Directory but not git — drill into it
      true ->
        new_value = "add #{path}/"
        suggestions = list_path_suggestions(path <> "/")

        {:noreply,
         socket
         |> assign(path_suggestions: suggestions, path_suggestion_selected: 0)
         |> push_event("set-input", %{value: new_value})}
    end
  end

  def handle_event("path-key", %{"key" => key}, socket) do
    suggestions = socket.assigns.path_suggestions
    max_idx = max(length(suggestions) - 1, 0)
    sel = socket.assigns.path_suggestion_selected

    case key do
      "ArrowDown" ->
        {:noreply, assign(socket, :path_suggestion_selected, min(sel + 1, max_idx))}

      "ArrowUp" ->
        {:noreply, assign(socket, :path_suggestion_selected, max(sel - 1, 0))}

      "Tab" ->
        suggestion = Enum.at(suggestions, sel)

        if suggestion do
          prefix = socket.assigns.path_command_prefix || "add"

          wt_prefixes = ~w(wt info diff tasks log close merge pr preview mcp i d t l c m)

          # For wt/project selections, Tab selects immediately
          if prefix in wt_prefixes || (prefix in ["p", "/p", "project", "/project"] && !String.starts_with?(suggestion.path, "/")) do
            new_value = "#{prefix} #{suggestion.path}"
            {:noreply,
             socket
             |> push_event("set-input", %{value: new_value})
             |> assign(path_suggestions: [], path_suggestion_selected: 0)}
          else
            new_value = "#{prefix} #{suggestion.path}"

            if suggestion.is_git do
              {:noreply,
               socket
               |> push_event("set-input", %{value: new_value})
               |> assign(path_suggestions: [], path_suggestion_selected: 0)}
            else
              new_suggestions = list_path_suggestions(suggestion.path <> "/")

              {:noreply,
               socket
               |> push_event("set-input", %{value: new_value <> "/"})
               |> assign(path_suggestions: new_suggestions, path_suggestion_selected: 0)}
            end
          end
        else
          {:noreply, socket}
        end

      "Escape" ->
        {:noreply, assign(socket, path_suggestions: [], path_suggestion_selected: 0)}

      _ ->
        {:noreply, socket}
    end
  end

  # ── PubSub handlers ────────────────────────────────────

  @impl true
  def handle_info({:worktrees_update, state}, socket) do
    state = filter_state_for_project(state, socket.assigns.current_project)
    old_state = socket.assigns.worktrees_state

    # Detect completed worktrees
    messages = detect_worktree_events(old_state, state, socket.assigns.msg_counter)

    socket =
      socket
      |> assign(:worktrees_state, state)
      |> append_messages(messages)
      |> bump_counter(length(messages))

    {:noreply, socket}
  end

  def handle_info({:dispatcher_update, status}, socket) do
    old_agents = socket.assigns.agents
    new_agents = agents_to_list(status.agents)

    # Subscribe to new agents
    new_ids = MapSet.new(new_agents, & &1.id)
    old_ids = MapSet.new(old_agents, & &1.id)
    added = MapSet.difference(new_ids, old_ids)

    if connected?(socket) && MapSet.size(added) > 0 do
      for agent <- new_agents, MapSet.member?(added, agent.id) do
        Phoenix.PubSub.subscribe(@pubsub, "brewer:#{agent.id}")
      end
    end

    {:noreply,
     assign(socket,
       agents: new_agents,
       dispatcher_projects: status[:projects] || %{}
     )}
  end

  def handle_info({:agent_state, agent_state}, socket) do
    # Update agent in list
    agents =
      Enum.map(socket.assigns.agents, fn a ->
        if a.id == agent_state.id, do: agent_state, else: a
      end)

    {:noreply, assign(socket, :agents, agents)}
  end

  def handle_info({:agent_output, lines}, socket) when is_list(lines) do
    # Check if any streaming worktree matches
    streaming = socket.assigns.log_streaming

    # Find which agent this output belongs to
    brewer =
      Enum.find(socket.assigns.agents, fn a ->
        a.current_worktree && MapSet.member?(streaming, a.current_worktree.id)
      end)

    if brewer do
      text = Enum.join(lines, "\n")
      c = socket.assigns.msg_counter
      source = "brewer #{brewer.id}"
      msg = ChatMessage.brewer_event(c, text, source)
      socket = socket |> append_message(msg) |> update_counter()
      {:noreply, socket}
    else
      {:noreply, socket}
    end
  end

  def handle_info({:projects_update, projects}, socket) do
    {:noreply, assign(socket, :projects, projects)}
  end

  def handle_info(_msg, socket) do
    {:noreply, socket}
  end

  # ── Private ────────────────────────────────────────────

  defp apply_project(socket, project_id) do
    case Projects.get(project_id) do
      {:ok, project} ->
        state = Worktrees.get_state(project_id: project.id)
        c = socket.assigns.msg_counter
        msg = ChatMessage.system(c, "project → #{project.name}")

        socket
        |> assign(:current_project, project)
        |> assign(:worktrees_state, state)
        |> append_message(msg)
        |> update_counter()

      _ ->
        socket
    end
  end

  @persist_count 30

  defp append_message(socket, msg) do
    messages = socket.assigns.messages ++ [msg]
    messages = Enum.take(messages, -@max_messages)

    socket
    |> assign(:messages, messages)
    |> persist_messages(messages)
  end

  defp append_messages(socket, []), do: socket

  defp append_messages(socket, msgs) do
    messages = socket.assigns.messages ++ msgs
    messages = Enum.take(messages, -@max_messages)

    socket
    |> assign(:messages, messages)
    |> persist_messages(messages)
  end

  defp persist_messages(socket, messages) do
    recent = Enum.take(messages, -@persist_count)

    serialized =
      Enum.map(recent, fn msg ->
        %{
          id: msg.id,
          type: to_string(msg.type),
          source: msg.source,
          context_label: msg.context_label || "",
          body: msg.body,
          timestamp: if(msg.timestamp, do: DateTime.to_iso8601(msg.timestamp), else: nil)
        }
      end)

    push_event(socket, "persist-messages", %{messages: serialized})
  end

  defp update_counter(socket) do
    assign(socket, :msg_counter, socket.assigns.msg_counter + 1)
  end

  defp bump_counter(socket, 0), do: socket
  defp bump_counter(socket, n) do
    assign(socket, :msg_counter, socket.assigns.msg_counter + n)
  end

  defp apply_updates(socket, updates) do
    Enum.reduce(updates, socket, fn {key, val}, acc ->
      assign(acc, key, val)
    end)
  end

  defp subscribe_to_agents(agents) do
    for agent <- agents do
      Phoenix.PubSub.subscribe(@pubsub, "brewer:#{agent.id}")
    end
  end

  # Convert %{pid => BrewerState} map to list of BrewerState with pid set
  defp agents_to_list(agents) when is_map(agents) do
    Enum.map(agents, fn {pid, state} -> %{state | pid: pid} end)
  end

  defp agents_to_list(agents) when is_list(agents), do: agents

  defp filter_state_for_project(state, nil), do: state

  defp filter_state_for_project(state, project) do
    tasks =
      (state[:tasks] || [])
      |> Enum.filter(fn item ->
        case item do
          %{project_id: pid} -> pid == project.id
          %{worktree_id: wt_id} ->
            # Task — check if its worktree belongs to this project
            parent = Enum.find(state[:tasks] || [], &(&1.id == wt_id && &1.type == "worktree"))
            parent && parent.project_id == project.id
          _ -> true
        end
      end)

    %{state | tasks: tasks}
  end

  defp filter_projects(projects, "") do
    projects
  end

  defp filter_projects(projects, query) do
    q = String.downcase(query)
    Enum.filter(projects, fn p -> String.contains?(String.downcase(p.name), q) end)
  end

  defp detect_worktree_events(old_state, new_state, counter) do
    old_items = old_state[:tasks] || []
    new_items = new_state[:tasks] || []

    old_wts = old_items |> Enum.filter(&(&1.type == "worktree")) |> Map.new(&{&1.id, &1})
    new_wts = new_items |> Enum.filter(&(&1.type == "worktree")) |> Map.new(&{&1.id, &1})

    old_tasks = old_items |> Enum.filter(&(&1.type == "task")) |> Map.new(&{&1.id, &1})
    new_tasks = new_items |> Enum.filter(&(&1.type == "task")) |> Map.new(&{&1.id, &1})

    # Detect worktree status changes
    wt_events =
      Enum.flat_map(new_wts, fn {id, new_wt} ->
        old_wt = Map.get(old_wts, id)
        short = id |> to_string() |> String.replace_leading("wt-", "") |> String.slice(0, 6)

        cond do
          is_nil(old_wt) -> []

          old_wt.status != new_wt.status && new_wt.status == "done" ->
            [ChatMessage.brewer_event(counter, "● #{short} completed · #{new_wt.title}", "apothecary")]

          old_wt.status != new_wt.status && new_wt.status == "pr_open" ->
            pr_text = if new_wt.pr_url, do: " · #{new_wt.pr_url}", else: ""
            [ChatMessage.brewer_event(counter, "◎ #{short} PR opened#{pr_text}", "apothecary")]

          true -> []
        end
      end)

    # Detect task completions
    task_events =
      Enum.flat_map(new_tasks, fn {id, new_task} ->
        old_task = Map.get(old_tasks, id)

        if old_task && old_task.status != "done" && new_task.status == "done" do
          # Find parent worktree short id
          wt_short =
            new_task.worktree_id
            |> to_string()
            |> String.replace_leading("wt-", "")
            |> String.slice(0, 6)

          [ChatMessage.brewer_event(counter, "● #{wt_short} task completed · #{new_task.title}", "apothecary")]
        else
          []
        end
      end)

    wt_events ++ task_events
  end

  # ── Path autocomplete helpers ──────────────────────────

  defp expand_tilde("~/" <> rest), do: Path.join(System.get_env("HOME", "~"), rest)
  defp expand_tilde("~"), do: System.get_env("HOME", "~")
  defp expand_tilde(path), do: path

  defp list_path_suggestions(input) do
    input = String.trim(input)

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
          |> Enum.reject(&String.starts_with?(&1, "."))
          |> Enum.map(&Path.join(dir, &1))
          |> Enum.filter(&File.dir?/1)
          |> Enum.filter(fn full_path ->
            name = Path.basename(full_path)
            query == "" || String.contains?(String.downcase(name), String.downcase(query))
          end)
          |> Enum.sort_by(&Path.basename/1)
          |> Enum.take(10)
          |> Enum.map(fn full_path ->
            %{
              path: full_path,
              name: Path.basename(full_path),
              is_git: File.dir?(Path.join(full_path, ".git"))
            }
          end)

        {:error, _} ->
          []
      end
    end
  end

  defp list_project_suggestions(projects, query) do
    projects
    |> Enum.filter(fn p ->
      query == "" || String.contains?(String.downcase(p.name), String.downcase(query))
    end)
    |> Enum.take(10)
    |> Enum.map(fn p ->
      %{
        path: p.name,
        name: p.name,
        is_git: true
      }
    end)
  end

  defp list_worktree_suggestions(worktrees_state, query) do
    items = worktrees_state[:tasks] || []

    items
    |> Enum.filter(&(&1.type == "worktree" && &1.status not in ["merged", "cancelled"]))
    |> Enum.sort_by(& to_string(&1.updated_at), :desc)
    |> Enum.filter(fn wt ->
      query == "" ||
        String.contains?(String.downcase(wt.title), String.downcase(query)) ||
        String.contains?(to_string(wt.id), query)
    end)
    |> Enum.take(10)
    |> Enum.map(fn wt ->
      short = wt.id |> to_string() |> String.replace_leading("wt-", "") |> String.slice(0, 6)
      %{
        path: short,
        name: "#{short} · #{wt.title}",
        is_git: wt.status in ["open", "claimed"] && wt.assigned_brewer_id != nil
      }
    end)
  end
end
