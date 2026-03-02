defmodule Apothecary.BrewSchedulerTest do
  use ExUnit.Case

  alias Apothecary.{BrewScheduler, Ingredients}

  setup do
    # Clean up recipes between tests
    Enum.each(Ingredients.list_recipes(), fn recipe ->
      Ingredients.delete_recipe(recipe.id)
    end)

    :ok
  end

  describe "status/0" do
    test "returns scheduler status" do
      status = BrewScheduler.status()
      assert is_map(status)
      assert is_list(status.scheduled)
      assert is_integer(status.timer_count)
    end

    test "includes newly created enabled recipe" do
      {:ok, recipe} = Ingredients.create_recipe(%{title: "Test schedule", schedule: "0 0 * * *"})

      # Allow PubSub to propagate
      _ = :sys.get_state(BrewScheduler)

      status = BrewScheduler.status()
      scheduled_ids = Enum.map(status.scheduled, & &1.id)
      assert recipe.id in scheduled_ids

      entry = Enum.find(status.scheduled, &(&1.id == recipe.id))
      assert entry.has_timer == true
      assert entry.enabled == true
    end
  end

  describe "recipe PubSub reactions" do
    test "schedules timer when recipe is created" do
      {:ok, recipe} = Ingredients.create_recipe(%{title: "Auto-schedule", schedule: "0 0 * * *"})

      # Sync with BrewScheduler
      _ = :sys.get_state(BrewScheduler)

      status = BrewScheduler.status()
      entry = Enum.find(status.scheduled, &(&1.id == recipe.id))
      assert entry != nil
      assert entry.has_timer == true
    end

    test "removes timer when recipe is deleted" do
      {:ok, recipe} = Ingredients.create_recipe(%{title: "Delete me", schedule: "0 0 * * *"})
      _ = :sys.get_state(BrewScheduler)

      # Verify timer exists
      status = BrewScheduler.status()
      assert Enum.any?(status.scheduled, &(&1.id == recipe.id && &1.has_timer))

      # Delete recipe
      Ingredients.delete_recipe(recipe.id)
      _ = :sys.get_state(BrewScheduler)

      # Timer should be gone
      status = BrewScheduler.status()
      refute Enum.any?(status.scheduled, &(&1.id == recipe.id))
    end

    test "removes timer when recipe is disabled" do
      {:ok, recipe} = Ingredients.create_recipe(%{title: "Disable me", schedule: "0 0 * * *"})
      _ = :sys.get_state(BrewScheduler)

      # Verify timer exists
      status = BrewScheduler.status()
      assert Enum.any?(status.scheduled, &(&1.id == recipe.id && &1.has_timer))

      # Toggle disabled
      Ingredients.toggle_recipe(recipe.id)
      _ = :sys.get_state(BrewScheduler)

      status = BrewScheduler.status()
      entry = Enum.find(status.scheduled, &(&1.id == recipe.id))
      assert entry.has_timer == false
    end

    test "re-schedules timer when recipe is re-enabled" do
      {:ok, recipe} = Ingredients.create_recipe(%{title: "Re-enable", schedule: "0 0 * * *"})
      _ = :sys.get_state(BrewScheduler)

      # Disable
      Ingredients.toggle_recipe(recipe.id)
      _ = :sys.get_state(BrewScheduler)

      # Re-enable
      Ingredients.toggle_recipe(recipe.id)
      _ = :sys.get_state(BrewScheduler)

      status = BrewScheduler.status()
      entry = Enum.find(status.scheduled, &(&1.id == recipe.id))
      assert entry.has_timer == true
      assert entry.enabled == true
    end
  end
end
