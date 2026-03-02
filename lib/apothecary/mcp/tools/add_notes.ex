defmodule Apothecary.MCP.Tools.AddNotes do
  @moduledoc "Add progress notes to an ingredient or your concoction. Notes persist across brewer restarts — use for context survival."
  use Hermes.Server.Component, type: :tool

  alias Hermes.Server.Response

  schema do
    field(:notes, {:required, :string}, description: "The notes to add")

    field(:ingredient_id, :string,
      description: "Ingredient ID to annotate. If omitted, notes go on the concoction itself."
    )
  end

  @impl true
  def execute(params, frame) do
    concoction_id = frame.assigns[:concoction_id]
    target_id = params[:ingredient_id] || concoction_id

    unless target_id do
      response =
        Response.tool()
        |> Response.text("Error: provide ingredient_id or have a concoction session")

      {:reply, response, frame}
    else
      # If targeting an ingredient, verify it belongs to this concoction
      if params[:ingredient_id] && concoction_id do
        case Apothecary.Ingredients.get_ingredient(params[:ingredient_id]) do
          {:ok, ingredient} when ingredient.concoction_id != concoction_id ->
            response =
              Response.tool()
              |> Response.text(
                "Ingredient #{params[:ingredient_id]} belongs to a different concoction."
              )

            {:reply, response, frame}

          _ ->
            do_add_note(target_id, params.notes, frame)
        end
      else
        do_add_note(target_id, params.notes, frame)
      end
    end
  end

  defp do_add_note(target_id, notes, frame) do
    case Apothecary.Ingredients.add_note(target_id, notes) do
      {:ok, _} ->
        response =
          Response.tool()
          |> Response.text("Notes added to #{target_id}.")

        {:reply, response, frame}

      {:error, :not_found} ->
        response =
          Response.tool()
          |> Response.text("#{target_id} not found.")

        {:reply, response, frame}

      {:error, reason} ->
        response =
          Response.tool()
          |> Response.text("Failed to add notes: #{inspect(reason)}")

        {:reply, response, frame}
    end
  end
end
