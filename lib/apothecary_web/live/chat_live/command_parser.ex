defmodule ApothecaryWeb.ChatLive.CommandParser do
  @moduledoc "Parse user input into command tuples based on current context."

  alias ApothecaryWeb.ChatLive.Context

  @type parsed ::
          {:command, atom(), list()}
          | {:action, atom(), list()}
          | {:error, String.t()}

  # Bare commands — single words that can't be confused with task/worktree text
  @bare_commands %{
    "s" => :full_status,
    "status" => :full_status,
    "?" => :help,
    "help" => :help,
    ".." => :back,
    "back" => :back,
    "i" => :info,
    "info" => :info,
    "d" => :diff,
    "diff" => :diff,
    "t" => :tasks,
    "tasks" => :tasks,
    "l" => :log,
    "log" => :log,
    "c" => :close,
    "close" => :close,
    "m" => :merge,
    "merge" => :merge,
    "p" => :list_projects,
    "pr" => :pr,
    "preview" => :preview,
    "wb" => :switch_wb,
    "oracle" => :switch_oracle,
    "wt" => :last_worktree,
    "recurring" => :switch_recurring,
    "recipe" => :switch_recurring,
    "start" => :start,
    "stop" => :stop,
    "mcp" => :mcp_list,
    "add" => :add_project,
    "new" => :new_project,
    "sh" => :sh,
    "brewers" => :set_brewers
  }

  @spec parse(String.t(), Context.t()) :: parsed()
  def parse("", _context), do: {:error, "empty input"}

  # /command syntax — always treated as command
  def parse("/" <> rest, context), do: parse_command(String.trim(rest), context)

  # Bare text — try shortcuts first, then fall through to context action
  def parse(text, context) do
    trimmed = String.trim(text)

    case parse_as_bare_command(trimmed, context) do
      nil -> parse_context_action(trimmed, context)
      cmd -> cmd
    end
  end

  # ── Command parsing (slash only) ─────────────────────────

  defp parse_command(rest, context) do
    case String.split(rest, ~r/\s+/, parts: 2) do
      # Status & help
      ["s"] -> {:command, :full_status, []}
      ["status"] -> {:command, :full_status, []}
      ["help"] -> {:command, :help, []}

      # Context switching
      ["wb"] -> {:command, :switch_context, ["wb"]}
      ["oracle"] -> {:command, :switch_context, ["oracle"]}
      ["recurring"] -> {:command, :switch_context, ["recurring"]}
      ["recipe"] -> {:command, :switch_context, ["recurring"]}
      ["back"] -> {:command, :back, []}
      ["wt", id] -> {:command, :switch_context, ["wt:#{String.trim(id)}"]}
      ["wt"] -> {:command, :last_worktree, []}

      # Worktree ops — context or explicit id (full word + single letter)
      ["info"] -> parse_wt_command(:info, nil, context)
      ["i"] -> parse_wt_command(:info, nil, context)
      ["info", id] -> {:command, :info, [String.trim(id)]}
      ["i", id] -> {:command, :info, [String.trim(id)]}
      ["diff"] -> parse_wt_command(:diff, nil, context)
      ["d"] -> parse_wt_command(:diff, nil, context)
      ["diff", id] -> {:command, :diff, [String.trim(id)]}
      ["d", id] -> {:command, :diff, [String.trim(id)]}
      ["preview"] -> parse_wt_command(:preview, nil, context)
      ["preview", id] -> {:command, :preview, [String.trim(id)]}
      ["tasks"] -> parse_wt_command(:tasks, nil, context)
      ["t"] -> parse_wt_command(:tasks, nil, context)
      ["tasks", id] -> {:command, :tasks, [String.trim(id)]}
      ["t", id] -> {:command, :tasks, [String.trim(id)]}
      ["log"] -> parse_wt_command(:log, nil, context)
      ["l"] -> parse_wt_command(:log, nil, context)
      ["log", id] -> {:command, :log, [String.trim(id)]}
      ["l", id] -> {:command, :log, [String.trim(id)]}
      ["close"] -> parse_wt_command(:close, nil, context)
      ["c"] -> parse_wt_command(:close, nil, context)
      ["close", id] -> {:command, :close, [String.trim(id)]}
      ["c", id] -> {:command, :close, [String.trim(id)]}

      # Task ops — require wt context
      ["rm", rest_args] -> parse_task_command(:rm_task, rest_args, context)
      ["edit", rest_args] -> parse_task_command(:edit_task, rest_args, context)

      # Merge — context or explicit id
      ["merge"] -> parse_wt_command(:merge, nil, context)
      ["m"] -> parse_wt_command(:merge, nil, context)
      ["merge", id] -> {:command, :merge, [String.trim(id)]}
      ["m", id] -> {:command, :merge, [String.trim(id)]}

      # PR ops — context or explicit id
      ["pr"] -> parse_wt_command(:pr, nil, context)
      ["pr", "close"] -> parse_wt_command(:pr_close, nil, context)
      ["pr", "close " <> id] -> {:command, :pr_close, [String.trim(id)]}
      ["pr", id] -> {:command, :pr, [String.trim(id)]}

      # MCP — context or explicit id
      ["mcp"] -> parse_wt_command(:mcp_list, nil, context)
      ["mcp", sub] -> parse_mcp_command(sub, context)

      # Brewers
      ["start"] -> {:command, :start, []}
      ["start", count] -> {:command, :start, [count]}
      ["stop"] -> {:command, :stop, []}
      ["brewers", count] -> {:command, :set_brewers, [count]}

      # Project
      ["p"] -> {:command, :list_projects, []}
      ["p", name] -> {:command, :select_project, [String.trim(name)]}
      ["project"] -> {:command, :list_projects, []}
      ["project", name] -> {:command, :select_project, [String.trim(name)]}
      ["add", path] -> {:command, :add_project, [String.trim(path)]}
      ["new", path] -> {:command, :new_project, [String.trim(path)]}

      # Shell
      ["sh", cmd] -> {:command, :sh, [cmd]}
      ["sh"] -> {:error, "usage: /sh <command>"}

      _ -> {:error, "unknown command: /#{rest}"}
    end
  end

  # Bare commands: single word or word + arg
  defp parse_as_bare_command(text, context) do
    case String.split(text, ~r/\s+/, parts: 2) do
      [key] ->
        case Map.get(@bare_commands, String.downcase(key)) do
          nil -> nil
          :list_projects -> {:command, :list_projects, []}
          :switch_wb -> {:command, :switch_context, ["wb"]}
          :switch_oracle -> {:command, :switch_context, ["oracle"]}
          :switch_recurring -> {:command, :switch_context, ["recurring"]}
          :last_worktree -> {:command, :last_worktree, []}
          :start -> {:command, :start, []}
          :stop -> {:command, :stop, []}
          :pr -> parse_wt_command(:pr, nil, context)
          :preview -> parse_wt_command(:preview, nil, context)
          :mcp_list -> parse_wt_command(:mcp_list, nil, context)
          cmd when cmd in [:info, :diff, :tasks, :log, :close, :merge] -> parse_wt_command(cmd, nil, context)
          cmd -> {:command, cmd, []}
        end

      [key, arg] ->
        case Map.get(@bare_commands, String.downcase(key)) do
          nil -> nil
          :list_projects -> parse_project_arg(arg)
          :last_worktree -> {:command, :switch_context, ["wt:#{String.trim(arg)}"]}
          :start -> {:command, :start, [String.trim(arg)]}
          :add_project -> {:command, :add_project, [String.trim(arg)]}
          :new_project -> {:command, :new_project, [String.trim(arg)]}
          :sh -> {:command, :sh, [arg]}
          :set_brewers -> {:command, :set_brewers, [String.trim(arg)]}
          :pr -> {:command, :pr, [String.trim(arg)]}
          :preview -> {:command, :preview, [String.trim(arg)]}
          :mcp_list -> {:command, :mcp_list, [String.trim(arg)]}
          cmd when cmd in [:info, :diff, :tasks, :log, :close, :merge] ->
            {:command, cmd, [String.trim(arg)]}
          _ -> nil
        end

      _ ->
        nil
    end
  end

  # p <arg> — handle "p add /path", "p <name>"
  defp parse_project_arg(arg) do
    case String.split(String.trim(arg), ~r/\s+/, parts: 2) do
      ["add", path] -> {:command, :add_project, [String.trim(path)]}
      _ -> {:command, :select_project, [String.trim(arg)]}
    end
  end

  # ── Context actions (bare text that isn't a command) ────

  defp parse_context_action(text, :wb), do: {:action, :create_worktree, [text]}
  defp parse_context_action(text, :oracle), do: {:action, :ask_oracle, [text]}
  defp parse_context_action(text, {:wt, wt_id}), do: {:action, :add_task, [wt_id, text]}
  defp parse_context_action(text, :recurring), do: {:action, :create_recipe, [text]}

  # ── Worktree-scoped command helpers ──────────────────────

  # Resolves wt_id from context when no explicit id given
  defp parse_wt_command(cmd, nil, {:wt, wt_id}), do: {:command, cmd, [wt_id]}
  defp parse_wt_command(cmd, nil, _), do: {:error, "#{cmd} requires a worktree context or id"}

  # Task commands: /rm <n>, /edit <n> <text>
  defp parse_task_command(:rm_task, args, {:wt, wt_id}) do
    case String.trim(args) do
      "" -> {:error, "usage: /rm <task-number>"}
      n -> {:command, :rm_task, [wt_id, n]}
    end
  end

  defp parse_task_command(:edit_task, args, {:wt, wt_id}) do
    case String.split(String.trim(args), ~r/\s+/, parts: 2) do
      [n, text] -> {:command, :edit_task, [wt_id, n, text]}
      [_n] -> {:error, "usage: /edit <task-number> <new title>"}
      _ -> {:error, "usage: /edit <task-number> <new title>"}
    end
  end

  defp parse_task_command(cmd, _args, _context) do
    {:error, "#{cmd} requires a worktree context"}
  end

  # MCP subcommands: /mcp, /mcp add [id] <url>, /mcp rm [id] <name>
  defp parse_mcp_command(sub, context) do
    case String.split(String.trim(sub), ~r/\s+/, parts: 3) do
      ["add", url] ->
        # /mcp add <url> — use context
        parse_mcp_with_context(:mcp_add, [url], context)

      ["add", id_or_url, url] ->
        # /mcp add <id> <url> — explicit id
        {:command, :mcp_add, [id_or_url, url]}

      ["rm", name] ->
        # /mcp rm <name> — use context
        parse_mcp_with_context(:mcp_rm, [name], context)

      ["rm", id, name] ->
        # /mcp rm <id> <name>
        {:command, :mcp_rm, [id, name]}

      [id] ->
        # /mcp <id> — list for specific worktree
        {:command, :mcp_list, [id]}

      _ ->
        {:error, "usage: /mcp [add <url> | rm <name>]"}
    end
  end

  defp parse_mcp_with_context(cmd, extra_args, {:wt, wt_id}) do
    {:command, cmd, [wt_id | extra_args]}
  end

  defp parse_mcp_with_context(_cmd, _args, _context) do
    {:error, "mcp requires a worktree context or id"}
  end
end
