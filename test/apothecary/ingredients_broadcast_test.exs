defmodule Apothecary.IngredientsBroadcastTest do
  use ExUnit.Case

  alias Apothecary.Ingredients

  setup do
    # Subscribe to PubSub to receive broadcast messages
    Phoenix.PubSub.subscribe(Apothecary.PubSub, "ingredients:updates")

    # Create a concoction + ingredient for testing
    {:ok, concoction} =
      Ingredients.create_concoction(%{title: "Test concoction", status: "in_progress"})

    # Drain the creation broadcast
    receive do
      {:ingredients_update, _} -> :ok
    after
      200 -> :ok
    end

    {:ok, ingredient} =
      Ingredients.create_ingredient(%{
        title: "Test ingredient",
        concoction_id: concoction.id
      })

    # Drain the creation broadcast
    receive do
      {:ingredients_update, _} -> :ok
    after
      200 -> :ok
    end

    %{concoction: concoction, ingredient: ingredient}
  end

  test "close_ingredient broadcasts immediately", %{ingredient: ingredient} do
    {:ok, _closed} = Ingredients.close_ingredient(ingredient.id)

    # The broadcast should arrive immediately (within a few ms), not after the
    # 50ms debounce window. Use a tight timeout to verify immediacy.
    assert_receive {:ingredients_update, state}, 30

    # Verify the broadcast contains the updated ingredient as done
    done = Enum.find(state.tasks, &(&1.id == ingredient.id))
    assert done.status == "done"
  end

  test "completing multiple ingredients broadcasts separately", %{
    concoction: concoction,
    ingredient: ingredient1
  } do
    {:ok, ingredient2} =
      Ingredients.create_ingredient(%{
        title: "Second ingredient",
        concoction_id: concoction.id
      })

    # Drain creation broadcast
    receive do
      {:ingredients_update, _} -> :ok
    after
      200 -> :ok
    end

    # Complete first ingredient
    {:ok, _} = Ingredients.close_ingredient(ingredient1.id)

    # Should get immediate broadcast showing first ingredient done
    assert_receive {:ingredients_update, state1}, 30
    i1 = Enum.find(state1.tasks, &(&1.id == ingredient1.id))
    i2 = Enum.find(state1.tasks, &(&1.id == ingredient2.id))
    assert i1.status == "done"
    assert i2.status == "open"

    # Complete second ingredient
    {:ok, _} = Ingredients.close_ingredient(ingredient2.id)

    # Should get another immediate broadcast showing both done
    assert_receive {:ingredients_update, state2}, 30
    i1 = Enum.find(state2.tasks, &(&1.id == ingredient1.id))
    i2 = Enum.find(state2.tasks, &(&1.id == ingredient2.id))
    assert i1.status == "done"
    assert i2.status == "done"
  end
end
