defmodule Apothecary.MCP.Tools.CompleteTask do
  @moduledoc "Mark a task as completed"
  use Hermes.Server.Component, type: :tool

  alias Hermes.Server.Response

  schema do
    field(:task_id, {:required, :string}, description: "The task ID to complete (e.g. t-abc123)")

    field(:summary, :string, description: "Brief summary of what was done")
  end

  @impl true
  def execute(%{task_id: task_id} = params, frame) do
    worktree_id = Apothecary.MCP.Server.worktree_id(frame)

    # Verify task belongs to this brewer's worktree
    with {:ok, task} <- Apothecary.Worktrees.get_task(task_id),
         true <- is_nil(worktree_id) or task.worktree_id == worktree_id do
      summary = params[:summary] || "Completed"

      # Auto-claim if the task wasn't explicitly claimed yet
      if task.status == "open" do
        Apothecary.Worktrees.update_task(task_id, %{status: "in_progress"})
      end

      case Apothecary.Worktrees.close_task(task_id, summary) do
        {:ok, closed} ->
          if params[:summary] do
            Apothecary.Worktrees.add_note(task_id, summary)
          end

          # Include remaining tasks so the agent knows what to claim next
          remaining = remaining_tasks_summary(task.worktree_id, task_id)

          response =
            Response.tool()
            |> Response.text("Task #{closed.id} marked as done.#{remaining}")

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

  defp remaining_tasks_summary(worktree_id, just_completed_id) do
    remaining =
      Apothecary.Worktrees.list_tasks(worktree_id: worktree_id)
      |> Enum.reject(fn t -> t.status == "done" or t.id == just_completed_id end)
      |> Enum.sort_by(fn t -> {t.priority || 99, t.created_at || ""} end)

    if remaining == [] do
      "\n\nAll tasks in this worktree are done!"
    else
      lines =
        Enum.map(remaining, fn t ->
          icon = if t.status == "blocked", do: "[!]", else: "[ ]"
          "  #{icon} #{t.id}: #{t.title}"
        end)
        |> Enum.join("\n")

      next_claimable =
        Enum.find(remaining, fn t -> t.status in ["open"] end)

      next_hint =
        if next_claimable,
          do: "\n\nNext task to claim: #{next_claimable.id} (#{next_claimable.title})",
          else: ""

      "\n\nRemaining tasks:\n#{lines}#{next_hint}"
    end
  end
end
