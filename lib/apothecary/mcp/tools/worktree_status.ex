defmodule Apothecary.MCP.Tools.WorktreeStatus do
  @moduledoc "Get an overview of your assigned worktree and all its tasks"
  use Hermes.Server.Component, type: :tool

  alias Hermes.Server.Response

  schema do
  end

  @impl true
  def execute(_params, frame) do
    worktree_id = Apothecary.MCP.Server.worktree_id(frame)

    unless worktree_id do
      response = Response.tool() |> Response.text("Error: no worktree_id in session")
      {:reply, response, frame}
    else
      case Apothecary.Worktrees.get_worktree(worktree_id) do
        {:ok, worktree} ->
          tasks =
            Apothecary.Worktrees.list_tasks(worktree_id: worktree_id)

          total = length(tasks)
          done = Enum.count(tasks, &(&1.status == "done"))
          open = Enum.count(tasks, &(&1.status == "open"))
          blocked = Enum.count(tasks, &(&1.status == "blocked"))
          in_progress = Enum.count(tasks, &(&1.status == "in_progress"))

          task_lines =
            tasks
            |> Enum.sort_by(fn t -> {t.priority || 99, t.created_at || ""} end)
            |> Enum.map(fn t ->
              icon =
                case t.status do
                  "done" -> "[x]"
                  "in_progress" -> "[~]"
                  "blocked" -> "[!]"
                  _ -> "[ ]"
                end

              line = "  #{icon} #{t.id}: #{t.title}"

              if t.notes && t.notes != "" do
                line <> "\n      Notes: #{t.notes}"
              else
                line
              end
            end)
            |> Enum.join("\n")

          text = """
          Worktree: #{worktree.id}
          Title: #{worktree.title}
          Status: #{worktree.status}
          Description: #{worktree.description || "(none)"}
          Notes: #{worktree.notes || "(none)"}
          PR: #{worktree.pr_url || "(not yet created)"}

          Tasks: #{total} total (#{done} done, #{open} open, #{in_progress} in progress, #{blocked} blocked)
          #{if task_lines == "", do: "  (no tasks — consider decomposing this worktree)", else: task_lines}
          """

          response =
            Response.tool()
            |> Response.text(String.trim(text))

          {:reply, response, frame}

        {:error, :not_found} ->
          response =
            Response.tool()
            |> Response.text("Worktree #{worktree_id} not found.")

          {:reply, response, frame}
      end
    end
  end
end
