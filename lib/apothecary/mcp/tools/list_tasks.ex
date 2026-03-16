defmodule Apothecary.MCP.Tools.ListTasks do
  @moduledoc "List all tasks in your assigned worktree"
  use Hermes.Server.Component, type: :tool

  alias Hermes.Server.Response

  schema do
    field(:status, :string, description: "Optional filter: open, in_progress, done, blocked")
  end

  @impl true
  def execute(params, frame) do
    worktree_id = Apothecary.MCP.Server.worktree_id(frame)

    unless worktree_id do
      response = Response.tool() |> Response.text("Error: no worktree_id in session")
      {:reply, response, frame}
    else
      filters = [worktree_id: worktree_id]

      filters =
        if params[:status], do: Keyword.put(filters, :status, params[:status]), else: filters

      tasks =
        Apothecary.Worktrees.list_tasks(filters)
        |> Enum.reject(&Apothecary.Task.is_readonly_kind?(&1.kind))

      text =
        tasks
        |> Enum.sort_by(fn t -> {t.priority || 99, t.created_at || ""} end)
        |> Enum.map(&format_task/1)
        |> Enum.join("\n")

      result = if text == "", do: "No tasks in this worktree.", else: text

      response =
        Response.tool()
        |> Response.text(result)

      {:reply, response, frame}
    end
  end

  defp format_task(task) do
    status_icon =
      case task.status do
        "done" -> "[x]"
        "in_progress" -> "[~]"
        "blocked" -> "[!]"
        _ -> "[ ]"
      end

    blockers =
      if task.blockers != [],
        do: " (blocked by: #{Enum.join(task.blockers, ", ")})",
        else: ""

    "#{status_icon} #{task.id}: #{task.title} [P#{task.priority || 3}]#{blockers}"
  end
end
