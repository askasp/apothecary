defmodule ApothecaryWeb.ChatLive.CommandParser do
  @moduledoc "Parse user input into command tuples based on current context."

  alias ApothecaryWeb.ChatLive.Context

  @type parsed ::
          {:command, atom(), list()}
          | {:action, atom(), list()}
          | {:error, String.t()}

  # Bare-word commands that work without / prefix
  @bare_commands %{
    "s" => {:command, :full_status, []},
    "status" => {:command, :full_status, []},
    "help" => {:command, :help, []},
    "oracle" => {:command, :switch_context, ["oracle"]},
    "wb" => {:command, :switch_context, ["wb"]},
    "wt" => {:command, :last_worktree, []},
    "recurring" => {:command, :switch_context, ["recurring"]},
    "back" => {:command, :back, []},
    "start" => {:command, :start, []},
    "stop" => {:command, :stop, []},
    "tasks" => {:command, :tasks, []},
    "log" => {:command, :log, []}
  }

  @spec parse(String.t(), Context.t()) :: parsed()
  def parse("", _context), do: {:error, "empty input"}

  # /command syntax — always treated as command
  def parse("/" <> rest, context), do: parse_command(String.trim(rest), context)

  # Bare text — try as command first, then fall through to context action
  def parse(text, context) do
    trimmed = String.trim(text)

    case parse_as_bare_command(trimmed, context) do
      nil -> parse_context_action(trimmed, context)
      cmd -> cmd
    end
  end

  # ── Command parsing (shared by / and bare) ─────────────

  defp parse_command(rest, context) do
    case String.split(rest, ~r/\s+/, parts: 2) do
      ["s"] -> {:command, :full_status, []}
      ["status"] -> {:command, :full_status, []}
      ["help"] -> {:command, :help, []}
      ["oracle"] -> {:command, :switch_context, ["oracle"]}
      ["wb"] -> {:command, :switch_context, ["wb"]}
      ["recurring"] -> {:command, :switch_context, ["recurring"]}
      ["back"] -> {:command, :back, []}
      ["wt", id] -> {:command, :switch_context, ["wt:#{String.trim(id)}"]}
      ["wt"] -> {:command, :last_worktree, []}
      ["brewers", count] -> {:command, :set_brewers, [count]}
      ["start"] -> {:command, :start, []}
      ["start", count] -> {:command, :start, [count]}
      ["stop"] -> {:command, :stop, []}
      ["tasks"] -> {:command, :tasks, []}
      ["log"] -> {:command, :log, []}
      ["log", id] -> {:command, :log, [id]}
      ["close"] -> parse_context_command(:close, context)
      ["close", id] -> {:command, :close, [id]}
      ["pr"] -> parse_context_command(:pr, context)
      ["p"] -> {:command, :list_projects, []}
      ["p", "add " <> path] -> {:command, :add_project, [String.trim(path)]}
      ["p", name] -> {:command, :select_project, [String.trim(name)]}
      ["project"] -> {:command, :list_projects, []}
      ["project", "add " <> path] -> {:command, :add_project, [String.trim(path)]}
      ["project", name] -> {:command, :select_project, [String.trim(name)]}
      ["add", path] -> {:command, :add_project, [String.trim(path)]}
      ["new", path] -> {:command, :new_project, [String.trim(path)]}
      ["sh", cmd] -> {:command, :sh, [cmd]}
      ["sh"] -> {:error, "usage: sh <command>"}
      _ -> {:error, "unknown command: /#{rest}"}
    end
  end

  # Try matching bare text as a command (no / prefix)
  # Only exact single-word matches + a few with args
  defp parse_as_bare_command(text, _context) do
    case String.split(text, ~r/\s+/, parts: 2) do
      [word] ->
        Map.get(@bare_commands, String.downcase(word))

      [word, arg] ->
        case {String.downcase(word), arg} do
          {"wt", a} -> {:command, :switch_context, ["wt:#{String.trim(a)}"]}
          {"p", "add " <> path} -> {:command, :add_project, [String.trim(path)]}
          {"p", a} -> {:command, :select_project, [String.trim(a)]}
          {"project", "add " <> path} -> {:command, :add_project, [String.trim(path)]}
          {"project", a} -> {:command, :select_project, [String.trim(a)]}
          {"brewers", a} -> {:command, :set_brewers, [String.trim(a)]}
          {"start", a} -> {:command, :start, [String.trim(a)]}
          {"log", a} -> {:command, :log, [String.trim(a)]}
          {"close", a} -> {:command, :close, [String.trim(a)]}
          {"add", a} -> {:command, :add_project, [String.trim(a)]}
          {"new", a} -> {:command, :new_project, [String.trim(a)]}
          {"sh", a} -> {:command, :sh, [a]}
          _ -> nil
        end

      _ ->
        nil
    end
  end

  # ── Context actions (bare text that isn't a command) ────

  defp parse_context_action(text, :wb), do: {:action, :create_worktree, [text]}
  defp parse_context_action(text, :oracle), do: {:action, :ask_oracle, [text]}
  defp parse_context_action(text, {:wt, wt_id}), do: {:action, :add_task, [wt_id, text]}
  defp parse_context_action(text, :recurring), do: {:action, :create_recipe, [text]}

  # ── Context-specific command helpers ────────────────────

  defp parse_context_command(:close, {:wt, id}), do: {:command, :close, [id]}
  defp parse_context_command(:close, _), do: {:error, "close requires a worktree context"}
  defp parse_context_command(:pr, {:wt, id}), do: {:command, :pr, [id]}
  defp parse_context_command(:pr, _), do: {:error, "pr requires a worktree context"}
end
