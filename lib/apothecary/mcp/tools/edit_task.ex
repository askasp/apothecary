defmodule Apothecary.MCP.Tools.EditTask do
  @moduledoc "Edit a task's title, description, priority, or status."
  use Hermes.Server.Component, type: :tool

  alias Hermes.Server.Response

  schema do
    field(:task_id, {:required, :string}, description: "The task ID to edit (e.g. t-abc123)")
    field(:title, :string, description: "New title for the task")
    field(:description, :string, description: "New description for the task")
    field(:priority, :integer, description: "New priority 0-4 (0=critical, 3=default, 4=backlog)")
    field(:status, :string, description: "New status (open, in_progress, blocked, done)")
  end

  @impl true
  def execute(%{task_id: task_id} = params, frame) do
    worktree_id = Apothecary.MCP.Server.worktree_id(frame)

    with {:ok, task} <- Apothecary.Worktrees.get_task(task_id),
         true <- is_nil(worktree_id) or task.worktree_id == worktree_id do
      changes =
        %{}
        |> maybe_put(:title, params[:title])
        |> maybe_put(:description, params[:description])
        |> maybe_put(:priority, params[:priority])
        |> maybe_put(:status, params[:status])

      if changes == %{} do
        response =
          Response.tool()
          |> Response.text(
            "No changes provided. Specify at least one of: title, description, priority, status."
          )

        {:reply, response, frame}
      else
        case Apothecary.Worktrees.update_task(task_id, changes) do
          {:ok, updated} ->
            changed_fields = changes |> Map.keys() |> Enum.map_join(", ", &to_string/1)

            response =
              Response.tool()
              |> Response.text("Updated task #{updated.id} (#{changed_fields}): #{updated.title}")

            {:reply, response, frame}

          {:error, reason} ->
            response =
              Response.tool()
              |> Response.text("Failed to update task: #{inspect(reason)}")

            {:reply, response, frame}
        end
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

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)
end
