defmodule Apothecary.MCP.Tools.CreateIngredient do
  @moduledoc "Create a new ingredient in your assigned concoction. Use this to decompose complex work into trackable steps."
  use Hermes.Server.Component, type: :tool

  alias Hermes.Server.Response

  schema do
    field(:title, {:required, :string}, description: "Short title for the ingredient")

    field(:description, :string,
      description: "Detailed description of what needs to be done"
    )

    field(:priority, :integer,
      description: "Priority 0-4 (0=critical, 3=default, 4=backlog)"
    )
  end

  @impl true
  def execute(params, frame) do
    concoction_id = frame.assigns[:concoction_id]

    unless concoction_id do
      response = Response.tool() |> Response.text("Error: no concoction_id in session")
      {:reply, response, frame}
    else
      attrs = %{
        title: params.title,
        concoction_id: concoction_id,
        description: params[:description],
        priority: params[:priority] || 3
      }

      case Apothecary.Ingredients.create_ingredient(attrs) do
        {:ok, ingredient} ->
          response =
            Response.tool()
            |> Response.text("Created ingredient #{ingredient.id}: #{ingredient.title}")

          {:reply, response, frame}

        {:error, reason} ->
          response =
            Response.tool()
            |> Response.text("Failed to create ingredient: #{inspect(reason)}")

          {:reply, response, frame}
      end
    end
  end
end
