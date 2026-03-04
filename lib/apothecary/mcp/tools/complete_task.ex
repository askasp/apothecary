defmodule Apothecary.MCP.Tools.CompleteTask do
  @moduledoc "Mark a task as completed"
  use Hermes.Server.Component, type: :tool

  alias Hermes.Server.Response

  schema do
    field(:task_id, {:required, :string},
      description: "The task ID to complete (e.g. t-abc123)"
    )

    field(:summary, :string, description: "Brief summary of what was done")
  end

  @impl true
  def execute(%{task_id: task_id} = params, frame) do
    worktree_id = Apothecary.MCP.Server.worktree_id(frame)

    # Verify task belongs to this brewer's worktree
    with {:ok, task} <- Apothecary.Worktrees.get_task(task_id),
         true <- is_nil(worktree_id) or task.worktree_id == worktree_id do
      summary = params[:summary] || "Completed"

      case Apothecary.Worktrees.close_task(task_id, summary) do
        {:ok, closed} ->
          if params[:summary] do
            Apothecary.Worktrees.add_note(task_id, summary)
          end

          response =
            Response.tool()
            |> Response.text("Task #{closed.id} marked as done.")

          {:reply, response, frame}

        {:error, reason} ->
          response =
            Response.tool()
            |> Response.text("Failed to complete task: #{inspect(reason)}")

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
