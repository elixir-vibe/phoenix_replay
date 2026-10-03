defmodule PhoenixReplay.Web.Live.ShowTest do
  use ExUnit.Case, async: false

  import Phoenix.ConnTest
  import Phoenix.LiveViewTest

  alias PhoenixReplay.Storage
  alias PhoenixReplay.Test.Fixtures
  alias PhoenixReplay.Web.Playback

  @endpoint PhoenixReplay.Test.Endpoint

  setup do
    recording = Fixtures.counter_recording(id: "show", clicks: 2)
    Storage.save(Fixtures.storage(), recording)
    on_exit(fn -> Storage.clear(Fixtures.storage()) end)
    %{recording: recording}
  end

  defp assigns(view), do: :sys.get_state(view.pid).socket.assigns

  # Delivers the pending playback step now. Playback tests use recordings
  # with hour-long gaps, so the real timer cannot fire during the test.
  defp advance(view) do
    %{playing: {timer, ref}} = assigns(view)
    Process.cancel_timer(timer)
    send(view.pid, {:advance, ref})
    assigns(view)
  end

  test "starts at the first render and steps through events" do
    {:ok, view, html} = live(build_conn(), "/replay/show")

    assert html =~ "PhoenixReplay.Test.Live.Counter"
    assert assigns(view).index == 1

    render_click(view, "next")
    assert assigns(view).index == 2
    render_click(view, "previous")
    render_click(view, "previous")
    render_click(view, "previous")
    assert assigns(view).index == 0

    render_hook(view, "seek", %{"index" => 5})
    assert assigns(view).index == 5
    assert render(view) =~ "count: 2"
  end

  test "drives its own frame channel" do
    {:ok, view, _html} = live(build_conn(), "/replay/show")
    {:ok, other, _html} = live(build_conn(), "/replay/show")
    channel = assigns(view).channel

    assert channel != assigns(other).channel
    assert has_element?(view, ~s(iframe[src="/replay/show/frame?channel=#{channel}"]))

    Playback.subscribe(channel)
    render_hook(view, "seek", %{"index" => "3"})
    assert_receive {Playback, {:seek, 3}}

    Playback.frame_ready(channel)
    assert_receive {Playback, {:seek, 3}}
  end

  test "plays to the end at the chosen speed" do
    gap = :timer.hours(1)
    recording = Fixtures.counter_recording(id: "hours", clicks: 2)

    events =
      recording.events
      |> Enum.with_index()
      |> Enum.map(fn {event, i} -> %{event | at: i * gap} end)

    Storage.save(Fixtures.storage(), %{recording | events: events})
    {:ok, view, _html} = live(build_conn(), "/replay/hours")
    render_change(view, "speed", %{"speed" => "10"})
    render_click(view, "toggle")

    # Every event is an hour apart; at 10x the next one is due in six minutes.
    assert %{playing: {timer, _ref}} = assigns(view)
    assert Process.read_timer(timer) in (div(gap, 10) - 1_000)..div(gap, 10)

    assert [2, 3, 4, 5] = for(_ <- 1..4, do: advance(view).index)
    assert %{index: 5, playing: nil} = assigns(view)

    render_click(view, "toggle")
    assert %{index: 1} = assigns(view)
    render_click(view, "toggle")
    assert %{playing: nil} = assigns(view)
  end

  test "deletes the recording" do
    {:ok, view, _html} = live(build_conn(), "/replay/show")
    assert {:error, {:live_redirect, %{to: "/replay"}}} = render_click(view, "delete")
    assert Storage.fetch(Fixtures.storage(), "show") == {:error, :not_found}
  end

  test "responds 404 for missing and unauthorized recordings" do
    Storage.save(Fixtures.storage(), Fixtures.counter_recording(id: "secret-1"))

    assert_raise PhoenixReplay.Web.NotFoundError, fn -> live(build_conn(), "/replay/missing") end

    assert_raise PhoenixReplay.Web.NotFoundError, fn ->
      live(build_conn(), "/restricted/replay/secret-1")
    end

    assert {:ok, _view, _html} = live(build_conn(), "/replay/secret-1")
  end
end
