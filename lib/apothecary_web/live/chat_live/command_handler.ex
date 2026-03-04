defmodule ApothecaryWeb.ChatLive.CommandHandler do
  @moduledoc "Execute parsed commands, returning messages and socket updates."

  alias Apothecary.{Worktrees, Dispatcher, Projects}
  alias ApothecaryWeb.ChatLive.{ChatMessage, Context, Formatters}

  @doc """
  Execute a parsed command. Returns {messages, assign_updates} where
  assign_updates is a keyword list of assigns to merge into socket.
  """
  def execute({:command, cmd, args}, socket) do
    do_execute(cmd, args, socket.assigns)
  end

  def execute({:action, action, args}, socket) do
    do_action(action, args, socket.assigns)
  end

  def execute({:error, reason}, _socket) do
    {[ChatMessage.error(0, reason)], []}
  end

  # Commands

  defp do_execute(:full_status, _args, assigns) do
    state =
      if assigns.current_project do
        Worktrees.get_state(project_id: assigns.current_project.id)
      else
        Worktrees.get_state()
      end

    body = Formatters.format_status_tree(state, assigns.agents, assigns.current_project, assigns[:dispatcher_projects] || %{})
    c = assigns.msg_counter
    {[ChatMessage.status(c, body)], [msg_counter: c + 1]}
  end

  defp do_execute(:help, _args, assigns) do
    body = Formatters.format_help(assigns.context)
    c = assigns.msg_counter
    {[ChatMessage.system(c, body)], [msg_counter: c + 1]}
  end

  defp do_execute(:switch_context, [target], assigns) do
    case Context.switch(assigns.context, target) do
      {:ok, {:wt, wt_id} = new_ctx} ->
        stack = Context.push(assigns.context_stack, assigns.context)
        label = Context.label(new_ctx)
        c = assigns.msg_counter

        # Try to include worktree title
        title =
          case Worktrees.get_worktree(wt_id) do
            {:ok, wt} -> wt.title
            _ -> nil
          end

        body =
          if title,
            do: "context → #{label} #{title}",
            else: "context → #{label}"

        msg = ChatMessage.system(c, body)
        {[msg], [context: new_ctx, context_stack: stack, msg_counter: c + 1]}

      {:ok, new_ctx} ->
        stack = Context.push(assigns.context_stack, assigns.context)
        label = Context.label(new_ctx)
        hint = Context.prompt_hint(new_ctx)
        c = assigns.msg_counter
        msg = ChatMessage.system(c, "context → #{label} · #{hint}")
        {[msg], [context: new_ctx, context_stack: stack, msg_counter: c + 1]}

      {:error, reason} ->
        c = assigns.msg_counter
        {[ChatMessage.error(c, reason)], [msg_counter: c + 1]}
    end
  end

  defp do_execute(:back, _args, assigns) do
    {prev, stack} = Context.pop(assigns.context_stack)
    label = Context.label(prev)
    c = assigns.msg_counter
    msg = ChatMessage.system(c, "context → #{label}")
    {[msg], [context: prev, context_stack: stack, msg_counter: c + 1]}
  end

  defp do_execute(:list_projects, _args, assigns) do
    c = assigns.msg_counter
    projects = assigns.projects

    if projects == [] do
      {[ChatMessage.system(c, "no projects — add one with /p <path>")], [msg_counter: c + 1]}
    else
      body = Formatters.format_project_list(projects, assigns.current_project)
      {[ChatMessage.system(c, body)], [msg_counter: c + 1]}
    end
  end

  defp do_execute(:select_project, [name_or_id], assigns) do
    c = assigns.msg_counter
    projects = assigns.projects

    # Try matching by name (case-insensitive partial match), by id, or by path
    match =
      Enum.find(projects, fn p ->
        String.downcase(p.name) == String.downcase(name_or_id) ||
          p.id == name_or_id ||
          String.contains?(String.downcase(p.name), String.downcase(name_or_id))
      end)

    match =
      match ||
        (case Projects.get_by_path(expand_tilde(name_or_id) |> Path.expand()) do
           {:ok, p} -> p
           _ -> nil
         end)

    if match do
      state = Worktrees.get_state(project_id: match.id)
      msg = ChatMessage.system(c, "project → #{match.name}")
      {[msg], [current_project: match, worktrees_state: state, msg_counter: c + 1]}
    else
      {[ChatMessage.error(c, "project not found: #{name_or_id}\nuse \"add /path\" to add a new project")], [msg_counter: c + 1]}
    end
  end

  defp do_execute(:add_project, [path_input], assigns) do
    c = assigns.msg_counter
    path = expand_tilde(path_input) |> Path.expand()

    cond do
      not File.dir?(path) ->
        {[ChatMessage.error(c, "not a directory: #{path}")], [msg_counter: c + 1]}

      not File.dir?(Path.join(path, ".git")) ->
        {[ChatMessage.error(c, "not a git repo: #{path}")], [msg_counter: c + 1]}

      true ->
        # Check if already added
        case Projects.get_by_path(path) do
          {:ok, project} ->
            state = Worktrees.get_state(project_id: project.id)
            msg = ChatMessage.system(c, "project → #{project.name} (already added)")
            {[msg], [current_project: project, worktrees_state: state, msg_counter: c + 1]}

          {:error, _} ->
            case Projects.add(path) do
              {:ok, project} ->
                state = Worktrees.get_state(project_id: project.id)
                all_projects = Projects.list_active()
                msg = ChatMessage.system(c, "project → #{project.name} (added)")
                {[msg], [current_project: project, projects: all_projects, worktrees_state: state, msg_counter: c + 1]}

              {:error, reason} ->
                {[ChatMessage.error(c, "failed to add: #{inspect(reason)}")], [msg_counter: c + 1]}
            end
        end
    end
  end

  defp do_execute(:new_project, [path_input], assigns) do
    c = assigns.msg_counter
    path = expand_tilde(path_input) |> Path.expand()

    cond do
      File.exists?(path) && File.dir?(Path.join(path, ".git")) ->
        # Already a git repo — just add it
        do_execute(:add_project, [path_input], assigns)

      File.exists?(path) && !File.dir?(path) ->
        {[ChatMessage.error(c, "path exists and is not a directory: #{path}")], [msg_counter: c + 1]}

      true ->
        with :ok <- File.mkdir_p(path),
             {_, 0} <- System.cmd("git", ["init"], cd: path, stderr_to_stdout: true),
             {:ok, project} <- Projects.add(path) do
          state = Worktrees.get_state(project_id: project.id)
          all_projects = Projects.list_active()
          msg = ChatMessage.system(c, "project → #{project.name} (created)")
          {[msg], [current_project: project, projects: all_projects, worktrees_state: state, msg_counter: c + 1]}
        else
          {:error, reason} ->
            {[ChatMessage.error(c, "failed to create: #{inspect(reason)}")], [msg_counter: c + 1]}

          {output, _code} ->
            {[ChatMessage.error(c, "git init failed: #{output}")], [msg_counter: c + 1]}
        end
    end
  end

  defp do_execute(:set_brewers, [count_str], assigns) do
    c = assigns.msg_counter

    case Integer.parse(count_str) do
      {count, _} when count > 0 and count <= 10 ->
        if assigns.current_project do
          Dispatcher.set_agent_count(assigns.current_project.id, count)
          msg = ChatMessage.system(c, "brewers set to #{count}")
          {[msg], [msg_counter: c + 1]}
        else
          {[ChatMessage.error(c, "select a project first")], [msg_counter: c + 1]}
        end

      _ ->
        {[ChatMessage.error(c, "invalid count (1-10)")], [msg_counter: c + 1]}
    end
  end

  defp do_execute(:start, args, assigns) do
    c = assigns.msg_counter

    if assigns.current_project do
      count =
        case args do
          [n] ->
            case Integer.parse(n) do
              {v, _} -> v
              _ -> 1
            end

          _ ->
            1
        end

      Dispatcher.start_swarm(assigns.current_project.id, count)
      msg = ChatMessage.system(c, "started #{count} brewer(s)")
      {[msg], [msg_counter: c + 1]}
    else
      {[ChatMessage.error(c, "select a project first")], [msg_counter: c + 1]}
    end
  end

  defp do_execute(:stop, _args, assigns) do
    c = assigns.msg_counter

    if assigns.current_project do
      Dispatcher.stop_swarm(assigns.current_project.id)
      msg = ChatMessage.system(c, "stopped brewing")
      {[msg], [msg_counter: c + 1]}
    else
      {[ChatMessage.error(c, "select a project first")], [msg_counter: c + 1]}
    end
  end

  defp do_execute(:last_worktree, _args, assigns) do
    c = assigns.msg_counter
    items = assigns.worktrees_state[:tasks] || []

    # Find most recently updated active worktree
    last_wt =
      items
      |> Enum.filter(&(&1.type == "worktree" && &1.status not in ["merged", "cancelled"]))
      |> Enum.sort_by(& &1.updated_at, {:desc, DateTime})
      |> List.first()

    if last_wt do
      new_ctx = {:wt, last_wt.id}
      stack = Context.push(assigns.context_stack, assigns.context)
      short = short_id(last_wt.id)
      msg = ChatMessage.system(c, "context → wt:#{short} #{last_wt.title}")
      {[msg], [context: new_ctx, context_stack: stack, msg_counter: c + 1]}
    else
      {[ChatMessage.error(c, "no active worktrees")], [msg_counter: c + 1]}
    end
  end

  defp do_execute(:tasks, _args, assigns) do
    c = assigns.msg_counter

    case assigns.context do
      {:wt, wt_id} ->
        case Worktrees.get_worktree(wt_id) do
          {:ok, wt} ->
            {:ok, tasks} = Worktrees.children(wt_id)
            body = Formatters.format_tasks(tasks, wt)
            {[ChatMessage.status(c, body)], [msg_counter: c + 1]}

          _ ->
            {[ChatMessage.error(c, "worktree not found")], [msg_counter: c + 1]}
        end

      _ ->
        {[ChatMessage.error(c, "switch to a worktree first: /wt <id>")],
         [msg_counter: c + 1]}
    end
  end

  defp do_execute(:log, args, assigns) do
    c = assigns.msg_counter

    wt_id =
      case args do
        [id] ->
          id

        _ ->
          case assigns.context do
            {:wt, id} -> id
            _ -> nil
          end
      end

    if wt_id do
      streaming = assigns.log_streaming

      new_streaming =
        if MapSet.member?(streaming, wt_id) do
          MapSet.delete(streaming, wt_id)
        else
          MapSet.put(streaming, wt_id)
        end

      action = if MapSet.member?(new_streaming, wt_id), do: "enabled", else: "disabled"
      short = short_id(wt_id)
      msg = ChatMessage.system(c, "log streaming #{action} for #{short}")
      {[msg], [log_streaming: new_streaming, msg_counter: c + 1]}
    else
      {[ChatMessage.error(c, "specify worktree or switch context: /wt <id>")],
       [msg_counter: c + 1]}
    end
  end

  defp do_execute(:close, [id], _assigns) do
    c = 0

    case Worktrees.close_worktree(id, "cancelled") do
      {:ok, _} ->
        short = short_id(id)
        msg = ChatMessage.system(c, "closed worktree #{short}")
        {[msg], [msg_counter: c + 1]}

      {:error, reason} ->
        {[ChatMessage.error(c, "failed to close: #{inspect(reason)}")], [msg_counter: c + 1]}
    end
  end

  defp do_execute(:pr, [id], assigns) do
    c = assigns.msg_counter

    case Worktrees.get_worktree(id) do
      {:ok, wt} ->
        if wt.pr_url do
          msg = ChatMessage.system(c, "↗ PR · #{wt.title} · #{wt.pr_url}")
          {[msg], [msg_counter: c + 1]}
        else
          {[ChatMessage.error(c, "no PR for this worktree yet")], [msg_counter: c + 1]}
        end

      _ ->
        {[ChatMessage.error(c, "worktree not found")], [msg_counter: c + 1]}
    end
  end

  defp do_execute(:sh, [cmd], assigns) do
    c = assigns.msg_counter

    if assigns.current_project do
      dir = assigns.current_project.path

      try do
        {output, code} = System.cmd("sh", ["-c", cmd], cd: dir, stderr_to_stdout: true, env: [])
        status = if code == 0, do: "", else: "\n(exit #{code})"
        body = String.trim(output) <> status
        body = if body == "", do: "(no output)", else: body
        {[ChatMessage.system(c, "$ #{cmd}\n#{body}")], [msg_counter: c + 1]}
      rescue
        e ->
          {[ChatMessage.error(c, "sh failed: #{Exception.message(e)}")], [msg_counter: c + 1]}
      end
    else
      {[ChatMessage.error(c, "select a project first")], [msg_counter: c + 1]}
    end
  end

  defp do_execute(cmd, _args, assigns) do
    c = assigns.msg_counter
    {[ChatMessage.error(c, "unknown command: #{cmd}")], [msg_counter: c + 1]}
  end

  # Actions (bare text)

  defp do_action(:create_worktree, [text], assigns) do
    c = assigns.msg_counter

    if assigns.current_project do
      lines = String.split(text, "\n", trim: true)
      title = List.first(lines)
      task_titles = Enum.drop(lines, 1)

      case Worktrees.create_worktree(%{
             project_id: assigns.current_project.id,
             title: title,
             description: text,
             priority: 3
           }) do
        {:ok, wt} ->
          tasks =
            Enum.map(task_titles, fn t ->
              case Worktrees.create_task(%{worktree_id: wt.id, title: String.trim(t)}) do
                {:ok, task} -> task
                _ -> nil
              end
            end)
            |> Enum.reject(&is_nil/1)

          body = Formatters.format_worktree_created(wt, tasks)
          msg = ChatMessage.system(c, body)
          {[msg], [msg_counter: c + 1]}

        {:error, reason} ->
          {[ChatMessage.error(c, "failed: #{inspect(reason)}")], [msg_counter: c + 1]}
      end
    else
      {[ChatMessage.error(c, "select a project first (/p)")], [msg_counter: c + 1]}
    end
  end

  defp do_action(:ask_oracle, [text], assigns) do
    c = assigns.msg_counter

    if assigns.current_project do
      case Worktrees.create_worktree(%{
             project_id: assigns.current_project.id,
             title: text,
             kind: "question",
             priority: 3
           }) do
        {:ok, wt} ->
          short = short_id(wt.id)
          msg = ChatMessage.system(c, "○ oracle question queued  #{short}")
          {[msg], [msg_counter: c + 1]}

        {:error, reason} ->
          {[ChatMessage.error(c, "failed: #{inspect(reason)}")], [msg_counter: c + 1]}
      end
    else
      {[ChatMessage.error(c, "select a project first (/p)")], [msg_counter: c + 1]}
    end
  end

  defp do_action(:add_task, [worktree_id, text], assigns) do
    c = assigns.msg_counter

    case Worktrees.create_task(%{worktree_id: worktree_id, title: text}) do
      {:ok, task} ->
        # Get current task counts for inline progress
        {:ok, all_tasks} = Worktrees.children(worktree_id)
        done = Enum.count(all_tasks, &(&1.status == "done"))
        total = length(all_tasks)
        bar = Formatters.inline_progress(done, total)
        msg = ChatMessage.brewer_event(c, "+ task added · #{task.title} · #{done}/#{total} #{bar}", "apothecary")
        {[msg], [msg_counter: c + 1]}

      {:error, reason} ->
        {[ChatMessage.error(c, "failed: #{inspect(reason)}")], [msg_counter: c + 1]}
    end
  end

  defp do_action(:create_recipe, [text], assigns) do
    c = assigns.msg_counter

    if assigns.current_project do
      case Worktrees.create_recipe(%{
             title: text,
             project_id: assigns.current_project.id,
             schedule: "manual",
             priority: 3
           }) do
        {:ok, _recipe} ->
          msg = ChatMessage.system(c, "● recipe created: #{text}")
          {[msg], [msg_counter: c + 1]}

        {:error, reason} ->
          {[ChatMessage.error(c, "failed: #{inspect(reason)}")], [msg_counter: c + 1]}
      end
    else
      {[ChatMessage.error(c, "select a project first (/p)")], [msg_counter: c + 1]}
    end
  end

  defp short_id(id) do
    id |> to_string() |> String.replace_leading("wt-", "") |> String.slice(0, 6)
  end

  defp expand_tilde("~/" <> rest), do: Path.join(System.get_env("HOME", "~"), rest)
  defp expand_tilde("~"), do: System.get_env("HOME", "~")
  defp expand_tilde(path), do: path
end
