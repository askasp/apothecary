defmodule Apothecary.MCP.Tools.GetProjectContext do
  @moduledoc "Get shared project context. Returns knowledge saved by other agents working on the same project."
  use Hermes.Server.Component, type: :tool

  alias Hermes.Server.Response

  schema do
    field(:category, :string,
      description:
        "Optional category filter (e.g. 'architecture', 'conventions', 'patterns'). Omit to get all."
    )
  end

  @impl true
  def execute(params, frame) do
    worktree_id = Apothecary.MCP.Server.worktree_id(frame)

    with {:ok, project_id} <- resolve_project_id(worktree_id) do
      if params[:category] do
        get_single(project_id, params[:category], frame)
      else
        get_all(project_id, frame)
      end
    else
      {:error, msg} ->
        response = Response.tool() |> Response.text("Error: #{msg}")
        {:reply, response, frame}
    end
  end

  defp get_all(project_id, frame) do
    entries = Apothecary.ProjectContexts.list(project_id)

    text =
      if entries == [] do
        "No project context saved yet. Use save_project_context to share knowledge with other agents."
      else
        entries
        |> Enum.map(fn e ->
          header = "## #{e.category}"
          meta = if e.updated_by, do: "(updated by #{e.updated_by} at #{e.updated_at})", else: "(updated at #{e.updated_at})"
          "#{header}\n#{meta}\n\n#{e.content}"
        end)
        |> Enum.join("\n\n---\n\n")
      end

    response = Response.tool() |> Response.text(text)
    {:reply, response, frame}
  end

  defp get_single(project_id, category, frame) do
    case Apothecary.ProjectContexts.get(project_id, category) do
      {:ok, entry} ->
        meta = if entry.updated_by, do: "(updated by #{entry.updated_by} at #{entry.updated_at})", else: "(updated at #{entry.updated_at})"
        text = "## #{entry.category}\n#{meta}\n\n#{entry.content}"
        response = Response.tool() |> Response.text(text)
        {:reply, response, frame}

      {:error, :not_found} ->
        response = Response.tool() |> Response.text("No context found for category '#{category}'.")
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
