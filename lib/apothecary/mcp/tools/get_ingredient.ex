defmodule Apothecary.MCP.Tools.GetIngredient do
  @moduledoc "Get details of a specific ingredient"
  use Hermes.Server.Component, type: :tool

  alias Hermes.Server.Response

  schema do
    field(:ingredient_id, {:required, :string}, description: "The ingredient ID (e.g. t-abc123)")
  end

  @impl true
  def execute(%{ingredient_id: ingredient_id}, frame) do
    concoction_id = Apothecary.MCP.Server.concoction_id(frame)

    case Apothecary.Ingredients.get_ingredient(ingredient_id) do
      {:ok, ingredient} ->
        if concoction_id && ingredient.concoction_id != concoction_id do
          response =
            Response.tool()
            |> Response.text("Ingredient #{ingredient_id} belongs to a different concoction.")

          {:reply, response, frame}
        else
          text = """
          ID: #{ingredient.id}
          Title: #{ingredient.title}
          Status: #{ingredient.status}
          Priority: #{ingredient.priority || 3}
          Concoction: #{ingredient.concoction_id}
          Description: #{ingredient.description || "(none)"}
          Notes: #{ingredient.notes || "(none)"}
          Blockers: #{if ingredient.blockers == [], do: "(none)", else: Enum.join(ingredient.blockers, ", ")}
          Dependents: #{if ingredient.dependents == [], do: "(none)", else: Enum.join(ingredient.dependents, ", ")}
          """

          response =
            Response.tool()
            |> Response.text(String.trim(text))

          {:reply, response, frame}
        end

      {:error, :not_found} ->
        response =
          Response.tool()
          |> Response.text("Ingredient #{ingredient_id} not found.")

        {:reply, response, frame}
    end
  end
end
