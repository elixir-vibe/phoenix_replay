defmodule PhoenixReplay.Web.ComponentsTest do
  use ExUnit.Case, async: true

  alias PhoenixReplay.Recording.Event
  alias PhoenixReplay.Web.Components

  test "formats times" do
    assert Components.clock(65_432) == "1:05"
    assert Components.duration(12_000) == "12s"
    assert Components.duration(184_000) == "3m 4s"
    assert Components.timestamp(0) == "1970-01-01 00:00:00"
  end

  test "parses non-negative integers" do
    assert Components.parse_integer("3", 1) == 3
    assert Components.parse_integer(3, 1) == 3
    assert Components.parse_integer(-3, 1) == 1
    assert Components.parse_integer("-3", 1) == 1
    assert Components.parse_integer("3x", 1) == 1
    assert Components.parse_integer(nil, 1) == 1
  end

  test "labels events" do
    event = fn type, data -> Components.event_label(%Event{at: 0, type: type, data: data}) end

    assert event.(:event, %{name: "save", params: %{}}) == "save"

    assert event.(:event, %{
             name: "validate",
             params: %{"_target" => ["user"], "user" => %{"name" => "Dan"}}
           }) ==
             "validate: name=Dan"

    assert event.(:params, %{params: %{}, uri: "/a"}) == "navigate → /a"
    assert event.(:info, %{tag: :tick}) == "handle_info :tick"
    assert event.(:info, %{tag: nil}) == "handle_info"
    assert event.(:render, %{assigns: %{b: 1, a: 2}}) == "assigns a, b"
  end
end
