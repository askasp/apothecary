defmodule Apothecary.MCP.Tools.DeleteTask do
  @moduledoc "Delete a task from your worktree. Cleans up dependency references."
  use Hermes.Server.Component, type: :tool

  alias Hermes.Server.Response

  schema do
    field(:task_id, {:required, :string}, description: "The task ID to delete (e.g. t-abc123)")
  end

  @impl true
  def execute(%{task_id: task_id}, frame) do
    worktree_id = Apothecary.MCP.Server.worktree_id(frame)

    with {:ok, task} <- Apothecary.Worktrees.get_task(task_id),
         true <- is_nil(worktree_id) or task.worktree_id == worktree_id do
      case Apothecary.Worktrees.delete_task(task_id) do
        {:ok, deleted} ->
          response =
            Response.tool()
            |> Response.text("Deleted task #{deleted.id}: #{deleted.title}")

          {:reply, response, frame}

        {:error, reason} ->
          response =
            Response.tool()
            |> Response.text("Failed to delete task: #{inspect(reason)}")

          {:reply, response, frame}
      end
    else
      false ->
        response =
          Response.tool()
          |> Response.text("Task #{task_id} belongs to a different worktree.")

        {:reply, response, frame}

      {:error, :not_found} ->
        response =
          Response.tool()
          |> Response.text("Task #{task_id} not found.")

        {:reply, response, frame}
    end
  end
end
