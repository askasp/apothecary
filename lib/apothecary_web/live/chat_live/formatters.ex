defmodule ApothecaryWeb.ChatLive.Formatters do
  @moduledoc "Format status trees, task lists, and other structured output for chat display."

  alias Apothecary.Task

  @doc "Build the full status tree from worktrees state and agents."
  def format_status_tree(worktrees_state, agents, project, dispatcher_projects \\ %{}) do
    items = worktrees_state[:tasks] || []

    worktrees =
      items
      |> Enum.filter(&(&1.type == "worktree"))
      |> Enum.filter(&(&1.status not in ["merged", "cancelled"]))

    tasks = Enum.filter(items, &(&1.type == "task"))
    tasks_by_wt = Enum.group_by(tasks, & &1.worktree_id)

    agents_by_wt =
      agents
      |> Enum.filter(&(&1.status == :working && &1.current_worktree))
      |> Enum.group_by(& &1.current_worktree.id)

    project_name = if project, do: project.name, else: "all projects"

    # Brewer/status counts
    brewing = Enum.count(agents, &(&1.status == :working))
    idle = Enum.count(agents, &(&1.status == :idle))
    reviewing = Enum.count(worktrees, &(&1.status == "pr_open"))
    done_count = Enum.count(worktrees, &(&1.status == "done"))

    queued_count =
      Enum.count(worktrees, fn wt ->
        wt.status not in ["pr_open", "done"] && !Map.has_key?(agents_by_wt, wt.id)
      end)

    # Project pool info
    pool = if project, do: Map.get(dispatcher_projects, project.id), else: nil
    target = if pool, do: pool[:target_count] || 0, else: 0
    pool_status = if pool, do: pool[:status], else: :paused

    # Header
    status_label = if pool_status == :running, do: "⠋ running", else: "○ stopped"
    header = "#{project_name} · #{status_label} · #{target} brewer(s)\n"

    # Counts line
    counts_parts = []
    counts_parts = if brewing > 0, do: counts_parts ++ ["⠋ #{brewing} brewing"], else: counts_parts
    counts_parts = if idle > 0, do: counts_parts ++ ["◇ #{idle} idle"], else: counts_parts
    counts_parts = if reviewing > 0, do: counts_parts ++ ["◎ #{reviewing} reviewing"], else: counts_parts
    counts_parts = if queued_count > 0, do: counts_parts ++ ["○ #{queued_count} queued"], else: counts_parts
    counts_parts = if done_count > 0, do: counts_parts ++ ["● #{done_count} done"], else: counts_parts

    counts = if counts_parts != [], do: Enum.join(counts_parts, "  ") <> "\n", else: ""

    if worktrees == [] do
      header <> counts <> "\n  (no active worktrees)"
    else
      grouped = group_worktrees(worktrees, agents_by_wt)
      sections = build_sections(grouped, tasks_by_wt, agents_by_wt)

      header <> counts <> "\n" <> sections
    end
  end

  defp group_worktrees(worktrees, agents_by_wt) do
    groups = %{"running" => [], "reviewing" => [], "queued" => [], "done" => []}

    worktrees
    |> Enum.reduce(groups, fn wt, acc ->
      has_agent = Map.has_key?(agents_by_wt, wt.id)

      group =
        cond do
          has_agent -> "running"
          wt.status == "in_progress" -> "running"
          wt.status == "pr_open" -> "reviewing"
          wt.status == "done" -> "done"
          true -> "queued"
        end

      Map.update!(acc, group, &(&1 ++ [wt]))
    end)
    |> Enum.reject(fn {_k, v} -> v == [] end)
    |> Enum.sort_by(fn {group, _} ->
      %{"running" => 0, "reviewing" => 1, "queued" => 2, "done" => 3}[group] || 99
    end)
  end

  defp build_sections(grouped, tasks_by_wt, agents_by_wt) do
    grouped
    |> Enum.map(fn {group, wts} ->
      section_header =
        case group do
          "running" -> nil
          "reviewing" -> nil
          "queued" -> "│\n│ QUEUED"
          "done" -> "│\n│ DONE"
        end

      blocks =
        wts
        |> Enum.with_index()
        |> Enum.map(fn {wt, idx} ->
          is_last = idx == length(wts) - 1
          wt_tasks = Map.get(tasks_by_wt, wt.id, [])
          wt_agents = Map.get(agents_by_wt, wt.id, [])
          format_worktree_block(wt, wt_tasks, wt_agents, is_last && group in ["queued", "done"])
        end)

      lines =
        if section_header do
          [section_header | blocks]
        else
          blocks
        end

      Enum.join(lines, "\n")
    end)
    |> Enum.join("\n")
  end

  defp format_worktree_block(wt, tasks, agents, is_last_in_section) do
    short = short_id(wt.id)
    connector = if is_last_in_section, do: "└─", else: "├─"

    # Status dot and title formatting
    {dot, _title_style} =
      cond do
        agents != [] -> {"⠋ ", :active}
        wt.status == "pr_open" -> {"◎ ", :reviewing}
        wt.status == "done" -> {"● ", :done}
        true -> {"○ ", :queued}
      end

    kind_label = if wt.kind == "question", do: " [oracle]", else: ""
    header = "#{connector} #{dot}#{wt.title}  #{short}#{kind_label}"

    # Brewer assignment line
    agent_lines =
      Enum.map(agents, fn agent ->
        elapsed = format_elapsed(agent.started_at)
        port_info = if agent.worktree_path, do: "", else: ""
        "│ brewer #{agent.id} · #{elapsed}#{port_info}"
      end)

    # Review info for PR worktrees
    review_line =
      if wt.status == "pr_open" do
        pr_ref = if wt.pr_url, do: extract_pr_number(wt.pr_url), else: nil
        parts = []
        parts = if pr_ref, do: parts ++ ["##{pr_ref}"], else: parts
        parts = parts ++ ["ready for review"]

        if parts != [] do
          ["│ " <> Enum.join(parts, " · ")]
        else
          []
        end
      else
        []
      end

    # Task tree
    task_lines = format_task_tree(tasks)

    # Progress bar
    progress =
      if tasks != [] do
        done = Enum.count(tasks, &(&1.status == "done"))
        total = length(tasks)
        bar = progress_bar(done, total)
        ["│ #{bar} #{done}/#{total}"]
      else
        []
      end

    lines =
      [header] ++ agent_lines ++ review_line ++ task_lines ++ progress ++ ["│"]

    Enum.join(lines, "\n")
  end

  defp format_task_tree(tasks) do
    tasks
    |> Enum.sort_by(& &1.created_at)
    |> Enum.with_index()
    |> Enum.map(fn {task, idx} ->
      connector = if idx == length(tasks) - 1, do: "└─", else: "├─"
      dot = task_dot(task)
      "│ #{connector}#{dot}#{task.title}"
    end)
  end


  @doc "Format project list for /p command."
  def format_project_list(projects, current) do
    header = "PROJECTS\n"

    lines =
      projects
      |> Enum.map(fn p ->
        marker = if current && current.id == p.id, do: "● ", else: "○ "
        "  #{marker}#{p.name}  #{p.path}"
      end)
      |> Enum.join("\n")

    header <> lines <> "\n\n  /p <name> to switch · /add <path> to add"
  end

  @doc "Format worktree creation confirmation."
  def format_worktree_created(worktree, tasks) do
    short = short_id(worktree.id)
    header = "● created worktree #{short}\n  #{worktree.title}"

    if tasks == [] do
      header
    else
      task_lines =
        tasks
        |> Enum.with_index(1)
        |> Enum.map_join("\n", fn {task, n} -> "  #{n}. ○ #{task.title}" end)

      header <> "\n" <> task_lines
    end
  end

  @doc "Format a task list for /tasks command."
  def format_tasks(tasks, worktree) do
    short = short_id(worktree.id)
    header = "TASKS · #{worktree.title} #{short}\n"

    if tasks == [] do
      header <> "  (no tasks)"
    else
      lines =
        tasks
        |> Enum.sort_by(& &1.created_at)
        |> Enum.with_index(1)
        |> Enum.map_join("\n", fn {task, n} ->
          dot = task_dot(task)
          "  #{n}. #{dot}#{task.title}"
        end)

      header <> lines
    end
  end

  @doc "Small inline progress bar for events."
  def inline_progress(done, total) when total > 0 do
    filled = round(done / total * 4)
    empty = 4 - filled
    String.duplicate("█", filled) <> String.duplicate("░", empty)
  end

  def inline_progress(_, _), do: "░░░░"

  @doc "Format context-sensitive help."
  def format_help(context) do
    global = """
    SHORTCUTS (/ optional)
      s  status       i  info [id]
      ?  help         d  diff [id]
      .. back         t  tasks [id]
      p  projects     l  log [id]
      wt [id]         c  close [id]
      start [n]       m  merge [id]
      stop            pr [id]

    CONTEXT
      /wb              workbench
      /oracle          oracle
      /wt [id]         worktree (last active)
      /recipe          recurring tasks
      /back            pop context

    WORKTREE OPS
      /info [id]       worktree details
      /diff [id]       diff stat vs main
      /preview [id]    dev server preview
      /tasks [id]      list tasks
      /log [id]        toggle log stream
      /close [id]      discard worktree

    TASK OPS (wt context)
      /rm <n>          delete task
      /edit <n> <text> rename task

    PR OPS
      /pr [id]         show PR info
      /merge [id]      merge PR
      /pr close [id]   close PR

    MCP
      /mcp [id]        list servers
      /mcp add <url>   add server
      /mcp rm <name>   remove server

    BREWERS
      /start [n]       start brewing
      /stop            stop brewing
      /brewers <n>     set pool size

    PROJECT
      /p [name]        list/switch projects
      /add <path>      add project
      /new <path>      create project

    SHELL
      /sh <cmd>        run in project dir\
    """

    context_help =
      case context do
        :wb ->
          "\n\n  WORKBENCH (current)\n    type to create a worktree · extra lines become tasks"

        :oracle ->
          "\n\n  ORACLE (current)\n    type a question to ask the oracle"

        {:wt, _} ->
          "\n\n  WORKTREE (current)\n    type to add a task"

        :recurring ->
          "\n\n  RECURRING (current)\n    type to create a recipe"
      end

    global <> context_help
  end

  @doc "Format detailed worktree info for /info command."
  def format_worktree_info(wt, tasks, agents) do
    short = short_id(wt.id)
    done = Enum.count(tasks, &(&1.status == "done"))
    total = length(tasks)

    status_label =
      cond do
        agents != [] -> "⠋ brewing"
        wt.status == "pr_open" -> "◎ reviewing"
        wt.status == "done" -> "● done"
        true -> "○ queued"
      end

    header = "#{wt.title}  #{short}\n#{status_label}"

    pr_line = if wt.pr_url, do: "\nPR  #{wt.pr_url}", else: ""

    agent_lines =
      if agents != [] do
        lines = Enum.map(agents, fn a ->
          elapsed = format_elapsed(a.started_at)
          "  brewer #{a.id} · #{elapsed}"
        end)
        "\n\nBREWERS\n" <> Enum.join(lines, "\n")
      else
        ""
      end

    task_section =
      if tasks != [] do
        bar = progress_bar(done, total)
        task_lines =
          tasks
          |> Enum.sort_by(& &1.created_at)
          |> Enum.with_index(1)
          |> Enum.map_join("\n", fn {task, n} ->
            dot = task_dot(task)
            "  #{n}. #{dot}#{task.title}"
          end)

        "\n\nTASKS #{bar} #{done}/#{total}\n" <> task_lines
      else
        "\n\n  (no tasks)"
      end

    header <> pr_line <> agent_lines <> task_section
  end

  # ── Helpers ─────────────────────────────────────────────

  defp task_dot(%Task{status: "done"}), do: "● "
  defp task_dot(%Task{assigned_to: a}) when not is_nil(a), do: "⠋ "
  defp task_dot(_), do: "○ "

  defp progress_bar(done, total) when total > 0 do
    filled = round(done / total * 4)
    empty = 4 - filled
    String.duplicate("█", filled) <> String.duplicate("░", empty)
  end

  defp progress_bar(_, _), do: "░░░░"

  defp format_elapsed(nil), do: ""

  defp format_elapsed(started_at) do
    diff = DateTime.diff(DateTime.utc_now(), started_at, :second)

    cond do
      diff < 60 -> "#{diff}s"
      diff < 3600 -> "#{div(diff, 60)}m"
      true -> "#{div(diff, 3600)}h#{div(rem(diff, 3600), 60)}m"
    end
  end

  defp short_id(id) do
    id |> to_string() |> String.replace_leading("wt-", "") |> String.slice(0, 6)
  end

  defp extract_pr_number(nil), do: nil

  defp extract_pr_number(url) when is_binary(url) do
    case Regex.run(~r/\/pull\/(\d+)/, url) do
      [_, num] -> num
      _ -> nil
    end
  end
end
