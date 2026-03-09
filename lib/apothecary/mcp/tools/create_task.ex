defmodule Apothecary.MCP.Tools.CreateTask do
  @moduledoc "Create a new task in your assigned worktree. Use this to decompose complex work into trackable steps."
  use Hermes.Server.Component, type: :tool

  alias Hermes.Server.Response

  schema do
    field(:title, {:required, :string}, description: "Short title for the task")

    field(:description, :string, description: "Detailed description of what needs to be done")

    field(:priority, :integer, description: "Priority 0-4 (0=critical, 3=default, 4=backlog)")
  end

  @impl true
  def execute(params, frame) do
    worktree_id = Apothecary.MCP.Server.worktree_id(frame)

    unless worktree_id do
      response = Response.tool() |> Response.text("Error: no worktree_id in session")
      {:reply, response, frame}
    else
      attrs = %{
        title: params.title,
        worktree_id: worktree_id,
        description: params[:description],
        priority: params[:priority] || 3
      }

      case Apothecary.Worktrees.create_task(attrs) do
        {:ok, task} ->
          response =
            Response.tool()
            |> Response.text("Created task #{task.id}: #{task.title}")

          {:reply, response, frame}

        {:error, reason} ->
          response =
            Response.tool()
            |> Response.text("Failed to create task: #{inspect(reason)}")

          {:reply, response, frame}
      end
    end
  end
end
