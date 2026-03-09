defmodule Apothecary.MCP.Tools.AddNotes do
  @moduledoc "Add progress notes to a task or your worktree. Notes persist across brewer restarts — use for context survival."
  use Hermes.Server.Component, type: :tool

  alias Hermes.Server.Response

  schema do
    field(:notes, {:required, :string}, description: "The notes to add")

    field(:task_id, :string,
      description: "Task ID to annotate. If omitted, notes go on the worktree itself."
    )
  end

  @impl true
  def execute(params, frame) do
    worktree_id = Apothecary.MCP.Server.worktree_id(frame)
    target_id = params[:task_id] || worktree_id

    unless target_id do
      response =
        Response.tool()
        |> Response.text("Error: provide task_id or have a worktree session")

      {:reply, response, frame}
    else
      # If targeting a task, verify it belongs to this worktree
      if params[:task_id] && worktree_id do
        case Apothecary.Worktrees.get_task(params[:task_id]) do
          {:ok, task} when task.worktree_id != worktree_id ->
            response =
              Response.tool()
              |> Response.text("Task #{params[:task_id]} belongs to a different worktree.")

            {:reply, response, frame}

          _ ->
            do_add_note(target_id, params.notes, frame)
        end
      else
        do_add_note(target_id, params.notes, frame)
      end
    end
  end

  defp do_add_note(target_id, notes, frame) do
    case Apothecary.Worktrees.add_note(target_id, notes) do
      {:ok, _} ->
        response =
          Response.tool()
          |> Response.text("Notes added to #{target_id}.")

        {:reply, response, frame}

      {:error, :not_found} ->
        response =
          Response.tool()
          |> Response.text("#{target_id} not found.")

        {:reply, response, frame}

      {:error, reason} ->
        response =
          Response.tool()
          |> Response.text("Failed to add notes: #{inspect(reason)}")

        {:reply, response, frame}
    end
  end
end
