defmodule Apothecary.MCP.Tools.ClaimTask do
  @moduledoc "Claim a task by setting it to in_progress — signals you're actively working on it."
  use Hermes.Server.Component, type: :tool

  alias Hermes.Server.Response

  schema do
    field(:task_id, {:required, :string}, description: "The task ID to claim (e.g. t-abc123)")
  end

  @impl true
  def execute(%{task_id: task_id}, frame) do
    worktree_id = Apothecary.MCP.Server.worktree_id(frame)

    with {:ok, task} <- Apothecary.Worktrees.get_task(task_id),
         true <- is_nil(worktree_id) or task.worktree_id == worktree_id do
      case Apothecary.Worktrees.update_task(task_id, %{status: "in_progress"}) do
        {:ok, updated} ->
          response =
            Response.tool()
            |> Response.text("Claimed task #{updated.id}: #{updated.title}")

          {:reply, response, frame}

        {:error, reason} ->
          response =
            Response.tool()
            |> Response.text("Failed to claim task: #{inspect(reason)}")

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
