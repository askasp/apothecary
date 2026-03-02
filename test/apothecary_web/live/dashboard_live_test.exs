defmodule ApothecaryWeb.DashboardLiveTest do
  use ApothecaryWeb.ConnCase

  import Phoenix.LiveViewTest

  test "renders dashboard", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/")
    assert html =~ "Apothecary"
    assert html =~ "Concoctions"
    assert html =~ "Brew Control"
  end
end
