defmodule PhoenixReplay.Web.Player.PagesTest do
  use ExUnit.Case, async: true

  alias PhoenixReplay.Recording.Summary
  alias PhoenixReplay.Web.Player.Pages

  defp visit(pages) do
    summaries =
      for {id, at, duration} <- pages,
          do: %Summary{id: id, view: "V", connected_at: at, duration_ms: duration}

    Pages.new("visit", summaries)
  end

  test "places overlapping pages in lanes" do
    pages = visit([{"list", 0, 16_000}, {"tab", 2_000, 3_000}, {"next", 20_000, 1_000}])

    assert [%{id: "list", lane: 0}, %{id: "tab", lane: 1}, %{id: "next", lane: 0}] = pages.pages
    assert pages.lanes == 2
    assert pages.duration_ms == 21_000
  end

  test "goes on with the visit's clock when a page ends" do
    # A tab still open then goes on where the clock is.
    assert {:continue, %{id: "tab"}, 3_000} =
             Pages.after_page(visit([{"list", 0, 5_000}, {"tab", 2_000, 10_000}]), "list")

    # A tab closed while the page played is not gone back to; the next page waits.
    assert {:wait, %{id: "next"}, 4_000} =
             Pages.after_page(
               visit([{"list", 0, 16_000}, {"tab", 2_000, 3_000}, {"next", 20_000, 1_000}]),
               "list"
             )

    # Nothing after the last page.
    assert Pages.after_page(visit([{"list", 0, 16_000}, {"tab", 2_000, 3_000}]), "list") == nil
  end
end
