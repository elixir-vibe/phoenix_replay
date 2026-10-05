defmodule PhoenixReplay.Recordings.FilterTest do
  use ExUnit.Case, async: true

  alias PhoenixReplay.Recording.Summary
  alias PhoenixReplay.Recordings.Filter

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
      within: "7d",
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
