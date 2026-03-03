defmodule ApothecaryWeb.DashboardLiveTest do
  use ApothecaryWeb.ConnCase

  import Phoenix.LiveViewTest

  alias Apothecary.Ingredients

  setup do
    # Clean up recipes between tests
    Enum.each(Ingredients.list_recipes(), fn recipe ->
      Ingredients.delete_recipe(recipe.id)
    end)

    :ok
  end

  test "renders dashboard with stockroom tab active by default", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/")
    # No projects = empty state shown
    assert html =~ "No projects yet"
    assert html =~ "Workbench"
    assert html =~ "Recurring Concoctions"
  end

  test "switches to recurring brews tab", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")

    html =
      view
      |> element("button", "Recurring Concoctions")
      |> render_click()

    assert html =~ "Recurring Concoctions"
    assert html =~ "No recipes yet"
    assert html =~ "New Recipe"
  end

  test "shows recipe creation form", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")

    # Switch to recipes tab
    view |> element("button", "Recurring Concoctions") |> render_click()

    # Click new recipe button
    html = view |> element("button", "New Recipe") |> render_click()

    assert html =~ "recipe-form"
    assert html =~ "Schedule (cron expression)"
    assert html =~ "Create Recipe"
  end

  test "creates a recipe", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")

    # Switch to recipes tab
    view |> element("button", "Recurring Concoctions") |> render_click()

    # Show form
    view |> element("button", "New Recipe") |> render_click()

    # Submit form
    html =
      view
      |> form("#recipe-form", %{
        recipe: %{
          title: "Daily task",
          description: "Runs every day",
          schedule: "0 9 * * *",
          priority: "2"
        }
      })
      |> render_submit()

    assert html =~ "Daily task"
    assert html =~ "0 9 * * *"
    refute html =~ "No recipes yet"
  end

  test "rejects invalid cron expression", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")

    view |> element("button", "Recurring Concoctions") |> render_click()
    view |> element("button", "New Recipe") |> render_click()

    html =
      view
      |> form("#recipe-form", %{
        recipe: %{
          title: "Bad cron",
          schedule: "not valid cron"
        }
      })
      |> render_submit()

    assert html =~ "Invalid cron expression"
  end

  test "toggles recipe enabled state", %{conn: conn} do
    {:ok, recipe} =
      Ingredients.create_recipe(%{title: "Toggle test", schedule: "0 0 * * *"})

    {:ok, view, _html} = live(conn, ~p"/")
    view |> element("button", "Recurring Concoctions") |> render_click()

    # Should show as active initially
    html = render(view)
    assert html =~ "active"

    # Toggle to paused
    html =
      view
      |> element("button[phx-click=toggle-recipe][phx-value-id=#{recipe.id}]")
      |> render_click()

    assert html =~ "paused"
  end

  test "deletes a recipe", %{conn: conn} do
    {:ok, recipe} =
      Ingredients.create_recipe(%{title: "Delete me", schedule: "0 0 * * *"})

    {:ok, view, _html} = live(conn, ~p"/")
    view |> element("button", "Recurring Concoctions") |> render_click()

    # Verify recipe shows up
    html = render(view)
    assert html =~ "Delete me"

    # Delete it
    html =
      view
      |> element("button[phx-click=delete-recipe][phx-value-id=#{recipe.id}]")
      |> render_click()

    refute html =~ "Delete me"
  end

  test "edits a recipe", %{conn: conn} do
    {:ok, recipe} =
      Ingredients.create_recipe(%{
        title: "Original",
        description: "Original desc",
        schedule: "0 0 * * *",
        priority: 3
      })

    {:ok, view, _html} = live(conn, ~p"/")
    view |> element("button", "Recurring Concoctions") |> render_click()

    # Click edit
    view
    |> element("button[phx-click=edit-recipe][phx-value-id=#{recipe.id}]")
    |> render_click()

    # Should show edit form
    html = render(view)
    assert html =~ "Edit Recipe"
    assert html =~ "Update Recipe"

    # Submit edit
    html =
      view
      |> form("#recipe-form", %{
        recipe: %{
          title: "Updated title",
          description: "Updated desc",
          schedule: "30 8 * * MON-FRI",
          priority: "1"
        }
      })
      |> render_submit()

    assert html =~ "Updated title"
    assert html =~ "30 8 * * MON-FRI"
  end

  test "switches back to stockroom tab", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")

    # Go to recipes
    view |> element("button", "Recurring Concoctions") |> render_click()
    html = render(view)
    refute html =~ "No projects yet"

    # Go back to stockroom
    html = view |> element("button", "Workbench") |> render_click()
    # No projects = empty state shown
    assert html =~ "No projects yet"
  end
end
