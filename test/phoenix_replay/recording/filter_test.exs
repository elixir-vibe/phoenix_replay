defmodule PhoenixReplay.Recording.FilterTest do
  use ExUnit.Case, async: true

  alias PhoenixReplay.Recording.{Filter, Summary}

  @now 10_000_000

  defp summary(id, attrs) do
    struct!(
      %Summary{id: id, view: "MyAppWeb.PageLive", connected_at: @now, url: "http://x/#{id}"},
      attrs
    )
  end

  defp ids(params, summaries) do
    params
    |> Filter.from_params()
    |> then(&Filter.select(summaries, &1, @now))
    |> Enum.map(& &1.id)
  end

  test "parses params, ignoring blanks and invalid values" do
    assert Filter.from_params(%{
             "q" => "  checkout ",
             "view" => "",
             "event" => "save",
             "within" => "2y",
             "min_events" => "-3"
           }) == %Filter{query: "checkout", event: "save"}

    assert Filter.from_params(%{"within" => "24h", "min_events" => "10"}) ==
             %Filter{within: "24h", min_events: 10}
  end

  test "round-trips through params" do
    filter = %Filter{
      query: "a",
      view: "V",
      event: "e",
      mark: "Paid",
      source: "google",
      medium: "cpc",
      campaign: "spring",
      device_type: "phone",
      browser: "Firefox",
      within: "7d",
      from: 1_791_274_440_000,
      to: 1_791_278_040_000,
      longer_than: 60,
      min_events: 3,
      errors: true,
      tab: "t1"
    }

    assert filter |> Filter.to_params() |> Filter.from_params() == filter
    assert Filter.to_params(%Filter{}) == %{}
    assert Filter.empty?(%Filter{})
    refute Filter.empty?(filter)
  end

  test "matches every criterion" do
    summaries = [
      summary("checkout-1", event_names: ["pay", "save"], event_count: 40),
      summary("home-1", view: "MyAppWeb.HomeLive", event_count: 5, tab: "t1"),
      summary("old-1", connected_at: @now - :timer.hours(48), event_count: 50, error_count: 2)
    ]

    assert ids(%{}, summaries) == ~w(checkout-1 home-1 old-1)
    assert ids(%{"q" => "CHECKOUT"}, summaries) == ~w(checkout-1)
    assert ids(%{"q" => "Pa"}, summaries) == ~w(checkout-1)
    assert ids(%{"view" => "MyAppWeb.HomeLive"}, summaries) == ~w(home-1)
    assert ids(%{"event" => "pay"}, summaries) == ~w(checkout-1)
    assert ids(%{"within" => "24h"}, summaries) == ~w(checkout-1 home-1)
    assert ids(%{"min_events" => "30"}, summaries) == ~w(checkout-1 old-1)
    assert ids(%{"errors" => "1"}, summaries) == ~w(old-1)
    assert ids(%{"tab" => "t1"}, summaries) == ~w(home-1)

    assert ids(%{"min_events" => "30", "within" => "7d", "event" => "save"}, summaries) ==
             ~w(checkout-1)
  end

  test "counts sessions by when they started, over the time it covers" do
    summaries = [
      summary("a", connected_at: 1_000),
      summary("b", connected_at: 1_500, error_count: 1),
      summary("c", connected_at: 2_100)
    ]

    assert Filter.histogram(summaries, %Filter{}, 1_000, @now) == [{1_000, 2, 1}, {2_000, 1, 0}]
    assert Filter.histogram(summaries, %Filter{errors: true}, 1_000, @now) == [{1_000, 1, 1}]

    assert Filter.time_range(%Filter{within: "1h"}, @now) == {@now - 3_600_000, @now}
    assert Filter.time_range(%Filter{from: 5, to: 9}, @now) == {5, 9}
    assert Filter.time_range(%Filter{from: 5}, @now) == {5, @now}
    assert Filter.time_range(%Filter{}, @now) == {@now - :timer.hours(24 * 30), @now}
  end

  test "matches where a visit came from, its device, marks and duration" do
    summaries = [
      summary("paid",
        source: "google",
        medium: "cpc",
        campaign: "spring",
        marks: %{"Paid" => 2},
        duration_ms: 90_000
      ),
      summary("phone",
        source: "(direct)",
        medium: "(none)",
        device_type: "phone",
        browser: "Firefox"
      )
    ]

    assert ids(%{"source" => "google", "medium" => "cpc"}, summaries) == ~w(paid)
    assert ids(%{"campaign" => "spring"}, summaries) == ~w(paid)
    assert ids(%{"source" => "(direct)"}, summaries) == ~w(phone)
    assert ids(%{"mark" => "Paid"}, summaries) == ~w(paid)
    assert ids(%{"device_type" => "phone", "browser" => "Firefox"}, summaries) == ~w(phone)
    assert ids(%{"device_type" => "watch"}, summaries) == ~w(paid phone)
    assert ids(%{"longer_than" => "60"}, summaries) == ~w(paid)
    assert ids(%{"q" => "SPRING"}, summaries) == ~w(paid)

    # A range of start times, in any offset.
    assert ids(%{"from" => "1970-01-01T02:46:40+00:00"}, summaries) == ~w(paid phone)
    assert ids(%{"from" => "1970-01-01T05:46:41+03:00"}, summaries) == []
    assert ids(%{"to" => "1970-01-01T02:46:39Z"}, summaries) == []
    assert ids(%{"from" => "yesterday"}, summaries) == ~w(paid phone)

    # A field's own criterion leaves its other values on offer.
    filter = Filter.from_params(%{"source" => "google"})

    assert Filter.count_values(summaries, :source, filter, @now, 10) == [
             {"(direct)", 1},
             {"google", 1}
           ]

    assert Filter.count_values(summaries, :mark, filter, @now, 10) == [{"Paid", 1}]
  end

  test "pages matches within a time range and counts them all" do
    summaries =
      for at <- 5..1//-1, do: summary("s#{at}", connected_at: at, error_count: rem(at, 2))

    page = &Filter.page(summaries, Filter.from_params(&1), [now: @now] ++ &2)
    ids = fn {matches, total} -> {Enum.map(matches, & &1.id), total} end

    assert ids.(page.(%{}, offset: 1, limit: 2)) == {~w(s4 s3), 5}
    assert ids.(page.(%{"errors" => "1"}, limit: 10)) == {~w(s5 s3 s1), 3}
    assert ids.(page.(%{}, until: 4, since: 2, limit: 10)) == {~w(s4 s3), 2}
    assert ids.(page.(%{}, limit: 0)) == {[], 5}
  end

  test "names the earliest start a window allows" do
    assert Filter.started_after(Filter.from_params(%{"within" => "1h"}), @now) == @now - 3_600_000
    assert Filter.started_after(%Filter{}, @now) == nil
  end
end
