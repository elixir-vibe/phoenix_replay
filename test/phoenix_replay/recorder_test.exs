defmodule PhoenixReplay.RecorderTest do
  use ExUnit.Case, async: false

  import Phoenix.ConnTest
  import Phoenix.LiveViewTest

  alias PhoenixReplay.{Recorder, Recording, Storage}
  alias PhoenixReplay.Session.Buffer
  alias PhoenixReplay.Recording.{Event, Timeline}
  alias PhoenixReplay.Test.{Fixtures, Sessions}

  @endpoint PhoenixReplay.Test.Endpoint

  setup :setup_sessions

  setup do
    on_exit(fn -> Storage.clear(Fixtures.storage()) end)
  end

  defp setup_sessions(context), do: Sessions.setup_sessions(context)

  test "records events and render diffs without touching the view's assigns", %{
    sessions: sessions
  } do
    {:ok, view, _html, id} = Sessions.live(sessions, build_conn(), "/counter")

    render_click(view, "inc")
    render_click(view, "inc")
    render_click(view, "dec")
    send(view.pid, :reset)
    render(view)

    refute Enum.any?(
             Map.keys(:sys.get_state(view.pid).socket.assigns),
             &(to_string(&1) =~ "replay")
           )

    assert {:ok, %Recording{view: PhoenixReplay.Test.Live.Counter} = recording} = Buffer.fetch(id)
    assert recording.url == "http://www.example.com/counter"

    assert [
             :mount,
             :params,
             :render,
             :event,
             :render,
             :event,
             :render,
             :event,
             :render,
             :info,
             :render
           ] =
             Enum.map(recording.events, & &1.type)

    assert [0, 1, 2, 1, 0] =
             for(
               %Event{type: :render, data: %{assigns: %{count: count}}} <- recording.events,
               do: count
             )

    assert %Event{data: %{tag: :reset}} = Enum.find(recording.events, &(&1.type == :info))

    assert recording.events
           |> Enum.map(& &1.at)
           |> Enum.chunk_every(2, 1, :discard)
           |> Enum.all?(fn [a, b] -> a <= b end)
  end

  test "saves the recording when the view exits", %{sessions: sessions} do
    {:ok, view, _html, id} = Sessions.live(sessions, build_conn(), "/counter")
    render_click(view, "inc")

    assert Sessions.stop(sessions, view) == :persisted
    assert Buffer.fetch(id) == :error
    assert {:ok, recording} = Storage.fetch(Fixtures.storage(), id)
    assert Timeline.assigns_at(recording, Timeline.last_index(recording)).count == 1
  end

  test "sanitizes params and assigns", %{sessions: sessions} do
    {:ok, view, _html, id} = Sessions.live(sessions, build_conn(), "/form")
    render_change(view, "validate", %{"name" => "dan", "password" => "hunter2"})

    {:ok, recording} = Buffer.fetch(id)
    refute inspect(recording) =~ "hunter2"

    assert %{name: "dan", password: "[FILTERED]"} =
             Timeline.assigns_at(recording, Timeline.last_index(recording))
  end

  test "applies live session options", %{sessions: sessions} do
    {:ok, view, _html, id} = Sessions.live(sessions, build_conn(), "/limited/counter")
    for _ <- 1..5, do: render_click(view, "inc")

    assert {:ok, %{events: events}} = Buffer.fetch(id)
    assert length(events) == 3
  end

  test "records only the sampled share of sessions" do
    {:ok, view, _html} = live(build_conn(), "/unsampled/counter")
    render_click(view, "inc")

    refute Map.has_key?(:sys.get_state(view.pid).socket.private, :phoenix_replay)
  end

  test "records LiveViews not mounted at the router", %{sessions: sessions} do
    {:ok, view, _html} = live_isolated(build_conn(), PhoenixReplay.Test.Live.Embedded)
    id = Sessions.track(sessions, view)
    render_click(view, "inc")

    assert {:ok, %{url: nil, events: events}} = Buffer.fetch(id)
    assert Enum.any?(events, &(&1.type == :event))
    refute Enum.any?(events, &(&1.type == :params))
  end

  test "samples sessions from a uniform draw" do
    assert Recorder.sampled?(1.0, 0.99)
    refute Recorder.sampled?(0.0, 0.0)
    assert Recorder.sampled?(0.25, 0.25)
    refute Recorder.sampled?(0.25, 0.26)
  end

  test "rejects unknown live session options" do
    socket = %Phoenix.LiveView.Socket{}

    assert_raise ArgumentError, ~r/:storage/, fn ->
      PhoenixReplay.Recorder.on_mount([storage: Foo], %{}, %{}, socket)
    end
  end
end
