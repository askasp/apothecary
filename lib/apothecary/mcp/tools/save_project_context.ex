defmodule Apothecary.MCP.Tools.SaveProjectContext do
  @moduledoc "Save shared project context. Store knowledge about the project that other agents can reuse."
  use Hermes.Server.Component, type: :tool

  alias Hermes.Server.Response

  schema do
    field(:category, {:required, :string},
      description:
        "Category for this context (e.g. 'architecture', 'conventions', 'patterns', 'tech-stack', 'gotchas')"
    )

    field(:content, {:required, :string},
      description: "The context content to save. Will replace any existing content for this category."
    )
  end

  @impl true
  def execute(params, frame) do
    worktree_id = Apothecary.MCP.Server.worktree_id(frame)
    brewer_id = Apothecary.MCP.Server.brewer_id(frame)

    with {:ok, project_id} <- resolve_project_id(worktree_id) do
      updated_by = if brewer_id, do: "brewer-#{brewer_id}", else: worktree_id

      case Apothecary.ProjectContexts.save(project_id, params.category, params.content, updated_by) do
        {:ok, _entry} ->
          response =
            Response.tool()
            |> Response.text(
              "Saved project context for category '#{params.category}'. Other agents on this project can now access it."
            )

          {:reply, response, frame}

        {:error, reason} ->
          response =
            Response.tool()
            |> Response.text("Failed to save context: #{inspect(reason)}")

          {:reply, response, frame}
      end
    else
      {:error, msg} ->
        response = Response.tool() |> Response.text("Error: #{msg}")
        {:reply, response, frame}
    end
  end

  defp resolve_project_id(worktree_id) do
    case Apothecary.Worktrees.get_worktree(worktree_id) do
      {:ok, %{project_id: pid}} when not is_nil(pid) -> {:ok, pid}
      {:ok, _} -> {:error, "worktree has no project_id"}
      {:error, :not_found} -> {:error, "worktree #{worktree_id} not found"}
    end
  end
end
