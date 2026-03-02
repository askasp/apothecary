defmodule Apothecary.MCP.Tools.ConcoctionStatus do
  @moduledoc "Get an overview of your assigned concoction and all its ingredients"
  use Hermes.Server.Component, type: :tool

  alias Hermes.Server.Response

  schema do
  end

  @impl true
  def execute(_params, frame) do
    concoction_id = Apothecary.MCP.Server.concoction_id(frame)

    unless concoction_id do
      response = Response.tool() |> Response.text("Error: no concoction_id in session")
      {:reply, response, frame}
    else
      case Apothecary.Ingredients.get_concoction(concoction_id) do
        {:ok, concoction} ->
          ingredients =
            Apothecary.Ingredients.list_ingredients(concoction_id: concoction_id)

          total = length(ingredients)
          done = Enum.count(ingredients, &(&1.status == "done"))
          open = Enum.count(ingredients, &(&1.status == "open"))
          blocked = Enum.count(ingredients, &(&1.status == "blocked"))
          in_progress = Enum.count(ingredients, &(&1.status == "in_progress"))

          ingredient_lines =
            ingredients
            |> Enum.sort_by(fn t -> {t.priority || 99, t.id} end)
            |> Enum.map(fn t ->
              icon =
                case t.status do
                  "done" -> "[x]"
                  "in_progress" -> "[~]"
                  "blocked" -> "[!]"
                  _ -> "[ ]"
                end

              line = "  #{icon} #{t.id}: #{t.title}"

              if t.notes && t.notes != "" do
                line <> "\n      Notes: #{t.notes}"
              else
                line
              end
            end)
            |> Enum.join("\n")

          text = """
          Concoction: #{concoction.id}
          Title: #{concoction.title}
          Status: #{concoction.status}
          Description: #{concoction.description || "(none)"}
          Notes: #{concoction.notes || "(none)"}
          PR: #{concoction.pr_url || "(not yet created)"}

          Ingredients: #{total} total (#{done} done, #{open} open, #{in_progress} in progress, #{blocked} blocked)
          #{if ingredient_lines == "", do: "  (no ingredients — consider decomposing this concoction)", else: ingredient_lines}
          """

          response =
            Response.tool()
            |> Response.text(String.trim(text))

          {:reply, response, frame}

        {:error, :not_found} ->
          response =
            Response.tool()
            |> Response.text("Concoction #{concoction_id} not found.")

          {:reply, response, frame}
      end
    end
  end
end
