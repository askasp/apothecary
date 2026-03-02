defmodule Apothecary.MCP.Tools.AddDependency do
  @moduledoc "Wire a dependency between two ingredients: blocked_id cannot start until blocker_id is done"
  use Hermes.Server.Component, type: :tool

  alias Hermes.Server.Response

  schema do
    field(:blocked_id, {:required, :string},
      description: "Ingredient that is blocked (e.g. t-abc123)"
    )

    field(:blocker_id, {:required, :string},
      description: "Ingredient that must complete first (e.g. t-def456)"
    )
  end

  @impl true
  def execute(%{blocked_id: blocked_id, blocker_id: blocker_id}, frame) do
    concoction_id = Apothecary.MCP.Server.concoction_id(frame)

    # Verify both ingredients belong to this concoction
    with {:blocked, {:ok, blocked}} <-
           {:blocked, Apothecary.Ingredients.get_ingredient(blocked_id)},
         {:blocker, {:ok, blocker}} <-
           {:blocker, Apothecary.Ingredients.get_ingredient(blocker_id)},
         true <-
           is_nil(concoction_id) or
             (blocked.concoction_id == concoction_id and
                blocker.concoction_id == concoction_id) do
      case Apothecary.Ingredients.add_dependency(blocked_id, blocker_id) do
        {:ok, :added} ->
          response =
            Response.tool()
            |> Response.text("Dependency added: #{blocked_id} is blocked by #{blocker_id}")

          {:reply, response, frame}

        {:error, :self_dependency} ->
          response =
            Response.tool()
            |> Response.text("Cannot add self-dependency.")

          {:reply, response, frame}

        {:error, :cycle_detected} ->
          response =
            Response.tool()
            |> Response.text(
              "Cannot add dependency: would create a cycle " <>
                "(#{blocked_id} -> #{blocker_id} -> ... -> #{blocked_id})"
            )

          {:reply, response, frame}

        {:error, reason} ->
          response =
            Response.tool()
            |> Response.text("Failed to add dependency: #{inspect(reason)}")

          {:reply, response, frame}
      end
    else
      false ->
        response =
          Response.tool()
          |> Response.text("Both ingredients must belong to your concoction.")

        {:reply, response, frame}

      {:blocked, {:error, :not_found}} ->
        response =
          Response.tool()
          |> Response.text("Blocked ingredient #{blocked_id} not found.")

        {:reply, response, frame}

      {:blocker, {:error, :not_found}} ->
        response =
          Response.tool()
          |> Response.text("Blocker ingredient #{blocker_id} not found.")

        {:reply, response, frame}
    end
  end
end
