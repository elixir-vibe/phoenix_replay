defmodule PhoenixReplay.RecorderClientTest do
  use ExUnit.Case, async: false

  import Phoenix.ConnTest
  import Phoenix.LiveViewTest

  alias PhoenixReplay.Session.Buffer
  alias PhoenixReplay.Test.Sessions

  @endpoint PhoenixReplay.Test.Endpoint

  setup context, do: Sessions.setup_sessions(context)

  test "asks the browser to record the pointer and keeps its batches from the view",
       %{sessions: sessions} do
    {:ok, view, _html, id} = Sessions.live(sessions, build_conn(), "/pointer/counter")

    assert_push_event(view, "phx_replay:record", %{
      pointer: %{sample: 30, scroll: 100, flush: 500, max_points: 500}
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

  test "signals every recorded session, with client state on by default",
       %{sessions: sessions} do
    {:ok, view, _html, _id} = Sessions.live(sessions, build_conn(), "/counter")

    assert_push_event(view, "phx_replay:record", %{
      pointer: nil,
      state: %{flush: 1_000, max_entries: 200, max_key: 64, max_entry_bytes: 8_192}
    })
  end

  test "signals nothing for a session that is not recorded" do
    {:ok, view, _html} = live(build_conn(), "/unsampled/counter")
    refute_push_event(view, "phx_replay:record", %{})
  end

  test "keeps client state batches from the view, sanitized", %{sessions: sessions} do
    {:ok, view, _html, id} = Sessions.live(sessions, build_conn(), "/counter")

    render_hook(view, "phx_replay:state", %{
      "span" => 40,
      "e" => [
        [0, "search", %{"query" => "shoes", "token" => "t"}],
        [40, "search", %{"page" => 2}]
      ]
    })

    assert render(view) =~ "count"
    assert {:ok, recording} = Buffer.fetch(id)

    assert [
             %{
               type: :state,
               data: %{
                 span: 40,
                 entries: [
                   [0, "search", %{"query" => "shoes", "token" => "[FILTERED]"}],
                   [40, "search", %{"page" => 2}]
                 ]
               }
             }
           ] = Enum.filter(recording.events, &(&1.type == :state))

    refute Enum.any?(recording.events, &(&1.type == :event))
  end

  test "records a viewport the browser sends on its own, once per change", %{sessions: sessions} do
    {:ok, view, _html, id} = Sessions.live(sessions, build_conn(), "/counter")

    landscape = %{"width" => 844, "height" => 390, "dpr" => 3}
    render_hook(view, "phx_replay:viewport", landscape)
    render_hook(view, "phx_replay:viewport", landscape)
    render_hook(view, "phx_replay:viewport", %{"width" => "wide"})

    assert render(view) =~ "count"
    assert {:ok, recording} = Buffer.fetch(id)

    assert [%{type: :viewport, data: %{width: 844, height: 390, dpr: 3}}] =
             Enum.filter(recording.events, &(&1.type == :viewport))

    refute Enum.any?(recording.events, &(&1.type == :event))
  end
end
