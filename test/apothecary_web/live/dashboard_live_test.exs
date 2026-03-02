defmodule ApothecaryWeb.DashboardLiveTest do
  use ApothecaryWeb.ConnCase

  import Phoenix.LiveViewTest

  test "renders dashboard", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/")
    assert html =~ "BREW"
    assert html =~ "primary-input"
  end
end
