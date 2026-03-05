defmodule Apothecary.MCP.Server do
  @moduledoc """
  MCP server for brewer-to-orchestrator communication.

  Brewers connect via HTTP with query params ?brewer_id=N&worktree_id=wt-xxx.
  Tools are scoped to the brewer's assigned worktree.
  """

  use Hermes.Server,
    name: "apothecary",
    version: "1.0.0",
    capabilities: [:tools]

  component(Apothecary.MCP.Tools.ListTasks)
  component(Apothecary.MCP.Tools.GetTask)
  component(Apothecary.MCP.Tools.CreateTask)
  component(Apothecary.MCP.Tools.CompleteTask)
  component(Apothecary.MCP.Tools.EditTask)
  component(Apothecary.MCP.Tools.DeleteTask)
  component(Apothecary.MCP.Tools.AddNotes)
  component(Apothecary.MCP.Tools.AddDependency)
  component(Apothecary.MCP.Tools.WorktreeStatus)

  require Logger

  @doc """
  Extract worktree_id from the per-request transport query params.

  Uses frame.transport[:query_params] which is populated fresh on each HTTP
  request, avoiding the shared-frame bug where frame.assigns gets overwritten
  when multiple brewers connect to the same MCP server.
  """
  def worktree_id(frame) do
    query_params = frame.transport[:query_params] || %{}
    query_params["worktree_id"]
  end

  @doc "Extract brewer_id from per-request transport query params."
  def brewer_id(frame) do
    query_params = frame.transport[:query_params] || %{}
    query_params["brewer_id"]
  end

  @impl true
  def init(_client_info, frame) do
    # Query params are read per-request via worktree_id/1 and brewer_id/1.
    # We no longer store them in frame.assigns since that's shared across sessions.
    query_params = frame.transport[:query_params] || %{}
    brewer_id = query_params["brewer_id"]
    worktree_id = query_params["worktree_id"]

    if is_nil(brewer_id) or is_nil(worktree_id) do
      Logger.warning(
        "MCP connection missing params — brewer_id: #{inspect(brewer_id)}, " <>
          "worktree_id: #{inspect(worktree_id)}. Tools may not work correctly."
      )
    end

    {:ok, frame}
  end
end
