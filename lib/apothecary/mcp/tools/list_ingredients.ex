defmodule Apothecary.MCP.Tools.ListIngredients do
  @moduledoc "List all ingredients in your assigned concoction"
  use Hermes.Server.Component, type: :tool

  alias Hermes.Server.Response

  schema do
    field(:status, :string, description: "Optional filter: open, in_progress, done, blocked")
  end

  @impl true
  def execute(params, frame) do
    concoction_id = Apothecary.MCP.Server.concoction_id(frame)

    unless concoction_id do
      response = Response.tool() |> Response.text("Error: no concoction_id in session")
      {:reply, response, frame}
    else
      filters = [concoction_id: concoction_id]

      filters =
        if params[:status], do: Keyword.put(filters, :status, params[:status]), else: filters

      ingredients = Apothecary.Ingredients.list_ingredients(filters)

      text =
        ingredients
        |> Enum.sort_by(fn t -> {t.priority || 99, t.id} end)
        |> Enum.map(&format_ingredient/1)
        |> Enum.join("\n")

      result = if text == "", do: "No ingredients in this concoction.", else: text

      response =
        Response.tool()
        |> Response.text(result)

      {:reply, response, frame}
    end
  end

  defp format_ingredient(ingredient) do
    status_icon =
      case ingredient.status do
        "done" -> "[x]"
        "in_progress" -> "[~]"
        "blocked" -> "[!]"
        _ -> "[ ]"
      end

    blockers =
      if ingredient.blockers != [],
        do: " (blocked by: #{Enum.join(ingredient.blockers, ", ")})",
        else: ""

    "#{status_icon} #{ingredient.id}: #{ingredient.title} [P#{ingredient.priority || 3}]#{blockers}"
  end
end
