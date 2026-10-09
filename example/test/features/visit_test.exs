defmodule ExampleWeb.Features.VisitTest do
  use PhoenixTest.Playwright.Case, async: false

  setup do
    config = PhoenixReplay.Config.load()
    PhoenixReplay.Catalog.clear(config)
    on_exit(fn -> PhoenixReplay.Catalog.clear(config) end)
    :ok
  end

  test "a visit through two LiveViews is one row of the dashboard, with both pages", %{
    conn: conn
  } do
    conn
    |> visit("/?utm_source=newsletter&utm_medium=email&utm_campaign=launch")
    # Interacting before the LiveView connects would drop the event.
    |> assert_has("body .phx-connected")
    |> click_button("Active")
    # The search page has no interaction of its own; the visit keeps it.
    |> visit("/search")
    |> assert_has("body .phx-connected")
    |> visit("/replay")
    |> assert_has("li[id^='visit-']", count: 1)
    |> assert_has("li[id^='visit-']", text: "/ → /search")
    |> assert_has("li[id^='visit-']", text: "newsletter")
  end
end
