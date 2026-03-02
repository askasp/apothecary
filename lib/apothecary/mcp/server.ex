defmodule Apothecary.MCP.Server do
  @moduledoc """
  MCP server for brewer-to-orchestrator communication.

  Brewers connect via HTTP with query params ?brewer_id=N&concoction_id=wt-xxx.
  Tools are scoped to the brewer's assigned concoction.
  """

  use Hermes.Server,
    name: "apothecary",
    version: "1.0.0",
    capabilities: [:tools]

  component(Apothecary.MCP.Tools.ListIngredients)
  component(Apothecary.MCP.Tools.GetIngredient)
  component(Apothecary.MCP.Tools.CreateIngredient)
  component(Apothecary.MCP.Tools.CompleteIngredient)
  component(Apothecary.MCP.Tools.AddNotes)
  component(Apothecary.MCP.Tools.AddDependency)
  component(Apothecary.MCP.Tools.ConcoctionStatus)

  require Logger

  @impl true
  def init(_client_info, frame) do
    # Extract brewer context from HTTP query params
    query_params = frame.transport[:query_params] || %{}
    brewer_id = query_params["brewer_id"]
    concoction_id = query_params["concoction_id"]

    if is_nil(brewer_id) or is_nil(concoction_id) do
      Logger.warning(
        "MCP connection missing params — brewer_id: #{inspect(brewer_id)}, " <>
          "concoction_id: #{inspect(concoction_id)}. Tools may not work correctly."
      )
    end

    {:ok,
     frame
     |> assign(:brewer_id, brewer_id)
     |> assign(:concoction_id, concoction_id)}
  end
end
