defmodule Apothecary.RecipeTest do
  use ExUnit.Case, async: true

  alias Apothecary.Recipe

  describe "from_record/1" do
    test "builds a Recipe struct from a Mnesia tuple" do
      now = DateTime.utc_now() |> DateTime.to_iso8601()

      record =
        {:apothecary_recipes, "recipe-abc123", "Daily updates", "Run updates daily",
         "0 9 * * MON-FRI", true, 2,
         %{
           last_run_at: now,
           next_run_at: now,
           created_at: now,
           updated_at: now,
           notes: "some notes"
         }}

      recipe = Recipe.from_record(record)

      assert recipe.id == "recipe-abc123"
      assert recipe.title == "Daily updates"
      assert recipe.description == "Run updates daily"
      assert recipe.schedule == "0 9 * * MON-FRI"
      assert recipe.enabled == true
      assert recipe.priority == 2
      assert recipe.last_run_at == now
      assert recipe.next_run_at == now
      assert recipe.created_at == now
      assert recipe.updated_at == now
      assert recipe.notes == "some notes"
      assert recipe.type == "recipe"
    end

    test "handles nil data fields" do
      record =
        {:apothecary_recipes, "recipe-def456", "Test", nil, "* * * * *", false, 3,
         %{
           last_run_at: nil,
           next_run_at: nil,
           created_at: nil,
           updated_at: nil,
           notes: nil
         }}

      recipe = Recipe.from_record(record)

      assert recipe.id == "recipe-def456"
      assert recipe.enabled == false
      assert recipe.last_run_at == nil
      assert recipe.notes == nil
    end
  end

  describe "to_record/1" do
    test "converts a Recipe struct to a Mnesia tuple" do
      now = DateTime.utc_now() |> DateTime.to_iso8601()

      recipe = %Recipe{
        id: "recipe-abc123",
        title: "Daily updates",
        description: "Run updates daily",
        schedule: "0 9 * * MON-FRI",
        enabled: true,
        priority: 2,
        last_run_at: now,
        next_run_at: now,
        created_at: now,
        updated_at: now,
        notes: "some notes"
      }

      record = Recipe.to_record(recipe)

      assert elem(record, 0) == :apothecary_recipes
      assert elem(record, 1) == "recipe-abc123"
      assert elem(record, 2) == "Daily updates"
      assert elem(record, 3) == "Run updates daily"
      assert elem(record, 4) == "0 9 * * MON-FRI"
      assert elem(record, 5) == true
      assert elem(record, 6) == 2

      data = elem(record, 7)
      assert data.last_run_at == now
      assert data.next_run_at == now
      assert data.notes == "some notes"
    end

    test "roundtrip: from_record(to_record(recipe)) preserves data" do
      recipe = %Recipe{
        id: "recipe-rt",
        title: "Roundtrip",
        description: "Test roundtrip",
        schedule: "0 0 * * *",
        enabled: true,
        priority: 1,
        last_run_at: nil,
        next_run_at: nil,
        created_at: "2026-01-01T00:00:00Z",
        updated_at: "2026-01-01T00:00:00Z",
        notes: nil
      }

      result = recipe |> Recipe.to_record() |> Recipe.from_record()

      assert result.id == recipe.id
      assert result.title == recipe.title
      assert result.description == recipe.description
      assert result.schedule == recipe.schedule
      assert result.enabled == recipe.enabled
      assert result.priority == recipe.priority
    end
  end
end
