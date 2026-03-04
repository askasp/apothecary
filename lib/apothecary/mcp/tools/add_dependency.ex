defmodule Apothecary.MCP.Tools.AddDependency do
  @moduledoc "Wire a dependency between two tasks: blocked_id cannot start until blocker_id is done"
  use Hermes.Server.Component, type: :tool

  alias Hermes.Server.Response

  schema do
    field(:blocked_id, {:required, :string},
      description: "Task that is blocked (e.g. t-abc123)"
    )

    field(:blocker_id, {:required, :string},
      description: "Task that must complete first (e.g. t-def456)"
    )
  end

  @impl true
  def execute(%{blocked_id: blocked_id, blocker_id: blocker_id}, frame) do
    worktree_id = Apothecary.MCP.Server.worktree_id(frame)

    # Verify both tasks belong to this worktree
    with {:blocked, {:ok, blocked}} <-
           {:blocked, Apothecary.Worktrees.get_task(blocked_id)},
         {:blocker, {:ok, blocker}} <-
           {:blocker, Apothecary.Worktrees.get_task(blocker_id)},
         true <-
           is_nil(worktree_id) or
             (blocked.worktree_id == worktree_id and
                blocker.worktree_id == worktree_id) do
      case Apothecary.Worktrees.add_dependency(blocked_id, blocker_id) do
        {:ok, :added} ->
          response =
            Response.tool()
            |> Response.text("Dependency added: #{blocked_id} is blocked by #{blocker_id}")

          {:reply, response, frame}

        {:error, :self_dependency} ->
          response =
            Response.tool()
            |> Response.text("Cannot add self-dependency.")

          {:reply, response, frame}

        {:error, :cycle_detected} ->
          response =
            Response.tool()
            |> Response.text(
              "Cannot add dependency: would create a cycle " <>
                "(#{blocked_id} -> #{blocker_id} -> ... -> #{blocked_id})"
            )

          {:reply, response, frame}

        {:error, reason} ->
          response =
            Response.tool()
            |> Response.text("Failed to add dependency: #{inspect(reason)}")

          {:reply, response, frame}
      end
    else
      false ->
        response =
          Response.tool()
          |> Response.text("Both tasks must belong to your worktree.")

        {:reply, response, frame}

      {:blocked, {:error, :not_found}} ->
        response =
          Response.tool()
          |> Response.text("Blocked task #{blocked_id} not found.")

        {:reply, response, frame}

      {:blocker, {:error, :not_found}} ->
        response =
          Response.tool()
          |> Response.text("Blocker task #{blocker_id} not found.")

        {:reply, response, frame}
    end
  end
end
