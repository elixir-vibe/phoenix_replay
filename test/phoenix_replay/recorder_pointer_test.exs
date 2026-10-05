defmodule PhoenixReplay.RecorderPointerTest do
  use ExUnit.Case, async: false

  import Phoenix.ConnTest
  import Phoenix.LiveViewTest

  alias PhoenixReplay.Session.Buffer
  alias PhoenixReplay.Test.Sessions

  setup context, do: Sessions.setup_sessions(context)

  test "asks the browser to record the pointer and keeps its batches from the view",
       %{sessions: sessions} do
    {:ok, view, _html, id} = Sessions.live(sessions, build_conn(), "/pointer/counter")

    assert_push_event(view, "phx_replay:pointer", %{
      sample: 30,
      scroll: 100,
      flush: 500,
      max_points: 500
    })

    # The counter has no handle_event for it: reaching the view would crash it.
    render_hook(view, "phx_replay:pointer", %{
      "span" => 300,
      "m" => [0, 10, 20, 0],
      "p" => [],
      "s" => [0, 0, 40]
    })

    assert render(view) =~ "count"

    assert {:ok, recording} = Buffer.fetch(id)

    assert [%{type: :pointer, data: %{span: 300, moves: [0, 10, 20, 0], scrolls: [0, 0, 40]}}] =
             Enum.filter(recording.events, &(&1.type == :pointer))

    # Batches are not LiveView events.
    refute Enum.any?(
             recording.events,
             &match?(%{type: :event, data: %{name: "phx_replay:pointer"}}, &1)
           )
  end

  test "asks nothing without :pointer", %{sessions: sessions} do
    {:ok, view, _html, _id} = Sessions.live(sessions, build_conn(), "/counter")
    refute_push_event(view, "phx_replay:pointer", %{})
  end
end
