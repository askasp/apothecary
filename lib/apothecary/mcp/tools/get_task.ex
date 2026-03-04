defmodule Apothecary.MCP.Tools.GetTask do
  @moduledoc "Get details of a specific task"
  use Hermes.Server.Component, type: :tool

  alias Hermes.Server.Response

  schema do
    field(:task_id, {:required, :string}, description: "The task ID (e.g. t-abc123)")
  end

  @impl true
  def execute(%{task_id: task_id}, frame) do
    worktree_id = Apothecary.MCP.Server.worktree_id(frame)

    case Apothecary.Worktrees.get_task(task_id) do
      {:ok, task} ->
        if worktree_id && task.worktree_id != worktree_id do
          response =
            Response.tool()
            |> Response.text("Task #{task_id} belongs to a different worktree.")

          {:reply, response, frame}
        else
          text = """
          ID: #{task.id}
          Title: #{task.title}
          Status: #{task.status}
          Priority: #{task.priority || 3}
          Worktree: #{task.worktree_id}
          Description: #{task.description || "(none)"}
          Notes: #{task.notes || "(none)"}
          Blockers: #{if task.blockers == [], do: "(none)", else: Enum.join(task.blockers, ", ")}
          Dependents: #{if task.dependents == [], do: "(none)", else: Enum.join(task.dependents, ", ")}
          """

          response =
            Response.tool()
            |> Response.text(String.trim(text))

          {:reply, response, frame}
        end

      {:error, :not_found} ->
        response =
          Response.tool()
          |> Response.text("Task #{task_id} not found.")

        {:reply, response, frame}
    end
  end
end
