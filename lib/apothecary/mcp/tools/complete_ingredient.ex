defmodule Apothecary.MCP.Tools.CompleteIngredient do
  @moduledoc "Mark an ingredient as completed"
  use Hermes.Server.Component, type: :tool

  alias Hermes.Server.Response

  schema do
    field(:ingredient_id, {:required, :string},
      description: "The ingredient ID to complete (e.g. t-abc123)"
    )

    field(:summary, :string, description: "Brief summary of what was done")
  end

  @impl true
  def execute(%{ingredient_id: ingredient_id} = params, frame) do
    concoction_id = Apothecary.MCP.Server.concoction_id(frame)

    # Verify ingredient belongs to this brewer's concoction
    with {:ok, ingredient} <- Apothecary.Ingredients.get_ingredient(ingredient_id),
         true <- is_nil(concoction_id) or ingredient.concoction_id == concoction_id do
      summary = params[:summary] || "Completed"

      case Apothecary.Ingredients.close_ingredient(ingredient_id, summary) do
        {:ok, closed} ->
          if params[:summary] do
            Apothecary.Ingredients.add_note(ingredient_id, summary)
          end

          response =
            Response.tool()
            |> Response.text("Ingredient #{closed.id} marked as done.")

          {:reply, response, frame}

        {:error, reason} ->
          response =
            Response.tool()
            |> Response.text("Failed to complete ingredient: #{inspect(reason)}")

          {:reply, response, frame}
      end
    else
      false ->
        response =
          Response.tool()
          |> Response.text("Ingredient #{ingredient_id} belongs to a different concoction.")

        {:reply, response, frame}

      {:error, :not_found} ->
        response =
          Response.tool()
          |> Response.text("Ingredient #{ingredient_id} not found.")

        {:reply, response, frame}
    end
  end
end
