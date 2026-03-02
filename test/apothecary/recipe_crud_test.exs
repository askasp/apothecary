defmodule Apothecary.RecipeCRUDTest do
  use ExUnit.Case

  alias Apothecary.Ingredients

  setup do
    # Clean up recipes between tests
    Enum.each(Ingredients.list_recipes(), fn recipe ->
      Ingredients.delete_recipe(recipe.id)
    end)

    :ok
  end

  describe "create_recipe/1" do
    test "creates a recipe with valid cron expression" do
      attrs = %{
        title: "Daily deploy check",
        description: "Check if deploys are needed",
        schedule: "0 9 * * *",
        priority: 2
      }

      assert {:ok, recipe} = Ingredients.create_recipe(attrs)
      assert recipe.title == "Daily deploy check"
      assert recipe.description == "Check if deploys are needed"
      assert recipe.schedule == "0 9 * * *"
      assert recipe.priority == 2
      assert recipe.enabled == true
      assert String.starts_with?(recipe.id, "recipe-")
      assert recipe.created_at != nil
    end

    test "rejects invalid cron expression" do
      attrs = %{title: "Bad schedule", schedule: "not a cron"}
      assert {:error, {:invalid_schedule, _}} = Ingredients.create_recipe(attrs)
    end

    test "creates recipe with default values" do
      attrs = %{title: "Minimal recipe", schedule: "* * * * *"}
      assert {:ok, recipe} = Ingredients.create_recipe(attrs)
      assert recipe.enabled == true
      assert recipe.priority == 3
    end
  end

  describe "get_recipe/1" do
    test "returns recipe by ID" do
      {:ok, created} = Ingredients.create_recipe(%{title: "Test", schedule: "0 0 * * *"})
      assert {:ok, found} = Ingredients.get_recipe(created.id)
      assert found.id == created.id
      assert found.title == "Test"
    end

    test "returns error for unknown ID" do
      assert {:error, :not_found} = Ingredients.get_recipe("recipe-nonexistent")
    end
  end

  describe "list_recipes/1" do
    test "lists all recipes" do
      {:ok, _} = Ingredients.create_recipe(%{title: "Recipe 1", schedule: "0 0 * * *"})
      {:ok, _} = Ingredients.create_recipe(%{title: "Recipe 2", schedule: "0 12 * * *"})

      recipes = Ingredients.list_recipes()
      assert length(recipes) == 2
    end

    test "filters by enabled" do
      {:ok, r1} = Ingredients.create_recipe(%{title: "Enabled", schedule: "0 0 * * *"})
      {:ok, _r2} = Ingredients.create_recipe(%{title: "Also enabled", schedule: "0 12 * * *"})
      Ingredients.toggle_recipe(r1.id)

      enabled = Ingredients.list_recipes(enabled: true)
      disabled = Ingredients.list_recipes(enabled: false)

      assert length(enabled) == 1
      assert length(disabled) == 1
      assert hd(disabled).id == r1.id
    end
  end

  describe "update_recipe/2" do
    test "updates recipe fields" do
      {:ok, recipe} = Ingredients.create_recipe(%{title: "Original", schedule: "0 0 * * *"})

      assert {:ok, updated} =
               Ingredients.update_recipe(recipe.id, %{title: "Updated", priority: 1})

      assert updated.title == "Updated"
      assert updated.priority == 1
      assert updated.schedule == "0 0 * * *"
    end

    test "returns error for unknown ID" do
      assert {:error, :not_found} =
               Ingredients.update_recipe("recipe-nonexistent", %{title: "nope"})
    end
  end

  describe "delete_recipe/1" do
    test "deletes a recipe" do
      {:ok, recipe} = Ingredients.create_recipe(%{title: "To delete", schedule: "0 0 * * *"})
      assert {:ok, _} = Ingredients.delete_recipe(recipe.id)
      assert {:error, :not_found} = Ingredients.get_recipe(recipe.id)
    end

    test "returns error for unknown ID" do
      assert {:error, :not_found} = Ingredients.delete_recipe("recipe-nonexistent")
    end
  end

  describe "toggle_recipe/1" do
    test "toggles enabled status" do
      {:ok, recipe} = Ingredients.create_recipe(%{title: "Toggle test", schedule: "0 0 * * *"})
      assert recipe.enabled == true

      assert {:ok, toggled} = Ingredients.toggle_recipe(recipe.id)
      assert toggled.enabled == false

      assert {:ok, toggled_back} = Ingredients.toggle_recipe(recipe.id)
      assert toggled_back.enabled == true
    end
  end

  describe "mark_recipe_run/2" do
    test "updates last_run_at and next_run_at" do
      {:ok, recipe} = Ingredients.create_recipe(%{title: "Run test", schedule: "0 0 * * *"})
      next = "2026-03-03T09:00:00Z"

      assert {:ok, updated} = Ingredients.mark_recipe_run(recipe.id, next)
      assert updated.last_run_at != nil
      assert updated.next_run_at == next
    end
  end
end
