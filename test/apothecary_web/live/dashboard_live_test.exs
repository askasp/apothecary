defmodule ApothecaryWeb.DashboardLiveTest do
  use ApothecaryWeb.ConnCase

  import Phoenix.LiveViewTest

  alias Apothecary.{Worktrees, Projects}

  setup do
    # Clean up recipes between tests
    Enum.each(Worktrees.list_recipes(), fn recipe ->
      Worktrees.delete_recipe(recipe.id)
    end)

    # Clean up projects
    Enum.each(Projects.list_active(), fn project ->
      Projects.archive(project.id)
    end)

    :ok
  end

  defp create_project do
    path = System.tmp_dir!() |> Path.join("test_project_#{System.unique_integer([:positive])}")
    File.mkdir_p!(path)
    {:ok, project} = Projects.create(path, name: "TestProject")
    project
  end

  test "renders dashboard with empty state when no projects", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/")
    assert html =~ "NO PROJECT OPEN"
  end

  test "renders dashboard with tabs when project selected", %{conn: conn} do
    project = create_project()
    {:ok, _view, html} = live(conn, ~p"/projects/#{project.id}")
    assert html =~ "workbench"
    assert html =~ "recurring"
  end

  test "switches to recurring brews tab", %{conn: conn} do
    project = create_project()
    {:ok, view, _html} = live(conn, ~p"/projects/#{project.id}")

    html =
      view
      |> element("button", "recurring")
      |> render_click()

    assert html =~ "recurring"
    assert html =~ "no recurring worktrees yet"
    assert html =~ "new recipe"
  end

  test "shows recipe creation form", %{conn: conn} do
    project = create_project()
    {:ok, view, _html} = live(conn, ~p"/projects/#{project.id}")

    # Switch to recipes tab
    view |> element("button", "recurring") |> render_click()

    # Click new recipe button
    html = view |> element("button[phx-click=show-recipe-form]") |> render_click()

    assert html =~ "recipe-form"
    assert html =~ "recipe-form"
  end

  test "creates a recipe", %{conn: conn} do
    project = create_project()
    {:ok, view, _html} = live(conn, ~p"/projects/#{project.id}")

    # Switch to recipes tab
    view |> element("button", "recurring") |> render_click()

    # Show form
    view |> element("button[phx-click=show-recipe-form]") |> render_click()

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
    refute html =~ "no recurring worktrees yet"
  end

  test "rejects invalid cron expression", %{conn: conn} do
    project = create_project()
    {:ok, view, _html} = live(conn, ~p"/projects/#{project.id}")

    view |> element("button", "recurring") |> render_click()
    view |> element("button[phx-click=show-recipe-form]") |> render_click()

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
      Worktrees.create_recipe(%{title: "Toggle test", schedule: "0 0 * * *"})

    project = create_project()
    {:ok, view, _html} = live(conn, ~p"/projects/#{project.id}")
    view |> element("button", "recurring") |> render_click()

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
      Worktrees.create_recipe(%{title: "Delete me", schedule: "0 0 * * *"})

    project = create_project()
    {:ok, view, _html} = live(conn, ~p"/projects/#{project.id}")
    view |> element("button", "recurring") |> render_click()

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
      Worktrees.create_recipe(%{
        title: "Original",
        description: "Original desc",
        schedule: "0 0 * * *",
        priority: 3
      })

    project = create_project()
    {:ok, view, _html} = live(conn, ~p"/projects/#{project.id}")
    view |> element("button", "recurring") |> render_click()

    # Click edit
    view
    |> element("[phx-click=edit-recipe][phx-value-id=#{recipe.id}]")
    |> render_click()

    # Should show edit form
    html = render(view)
    assert html =~ "EDIT RECIPE"

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

  test "switches back to workbench tab", %{conn: conn} do
    project = create_project()
    {:ok, view, _html} = live(conn, ~p"/projects/#{project.id}")

    # Go to recipes
    view |> element("button", "recurring") |> render_click()
    html = render(view)
    refute html =~ "No projects yet"

    # Go back to workbench
    html = view |> element("button", "workbench") |> render_click()
    assert html =~ "workbench"
  end
end
