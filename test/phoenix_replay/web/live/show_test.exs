defmodule PhoenixReplay.Web.Live.ShowTest do
  use ExUnit.Case, async: false

  import Phoenix.ConnTest
  import Phoenix.LiveViewTest

  alias PhoenixReplay.{Config, Storage}
  alias PhoenixReplay.Recording.Event
  alias PhoenixReplay.Session.Buffer
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

  defp open_tab(view, name), do: view |> element(~s(button[role="tab"]), name) |> render_click()

  # Buffers a running session whose URL the redactor masks.
  defp buffer_live(id) do
    recording = %{
      Fixtures.counter_recording(id: id, clicks: 2)
      | url: "http://localhost/cards/4242"
    }

    redactor = {PhoenixReplay.Redactor.Patterns, patterns: [~r/\d{4}$/]}
    :ok = Buffer.open(recording, self(), %{Config.load() | redact: redactor})
    Buffer.put_url(id, recording.url)

    recording.events
    |> Enum.with_index()
    |> Enum.each(fn {event, seq} -> Buffer.append(id, seq, event) end)

    on_exit(fn -> Buffer.close(id) end)
    recording
  end

  # Delivers the pending playback step now. Playback tests use recordings
  # with hour-long gaps, so the real timer cannot fire during the test.
  defp advance(view) do
    %{playing: {timer, ref}} = assigns(view)
    Process.cancel_timer(timer)
    send(view.pid, {:advance, ref})
    assigns(view)
  end

  test "opens at a linked moment and links to the current one" do
    {:ok, view, _html} = live(build_conn(), "/replay/show?at=4")
    assert assigns(view).index == 4
    assert has_element?(view, ~s(button[data-copy="/replay/show?at=4"]), "Copy link to 0:02")

    render_click(view, "next")
    assert has_element?(view, ~s(button[data-copy="/replay/show?at=5"]))
  end

  test "groups events by interaction, filters them and marks what changed" do
    {:ok, view, _html} = live(build_conn(), "/replay/show")

    # mount leads with its render; each click leads with its render.
    assert has_element?(view, "#replay-events > li:nth-child(1) li", "assigns count")
    assert has_element?(view, "#replay-events > li:nth-child(2) > button", "inc")

    nested =
      view |> render() |> LazyHTML.from_document() |> LazyHTML.query("#replay-events li li")

    assert Enum.count(nested) == 3

    view |> element("#replay-event-search") |> render_change(%{"q" => "nothing"})
    assert has_element?(view, "#replay-events li", "No events match.")
    view |> element("#replay-event-search") |> render_change(%{"q" => ""})

    open_tab(view, "State")
    assert has_element?(view, "#replay-assigns summary.bg-accent-soft", "count")
  end

  test "jumps to the first error" do
    recording = Fixtures.counter_recording(id: "failing")
    error = %Event{at: 1500, type: :log, data: %{level: :error, message: "boom", metadata: %{}}}
    events = List.insert_at(recording.events, 4, error)
    Storage.save(Fixtures.storage(), %{recording | events: events})

    {:ok, view, _html} = live(build_conn(), "/replay/failing")
    view |> element("button", "1 error · jump to first") |> render_click()

    assert assigns(view).index == 4
    assert has_element?(view, "#replay-events dd", "boom")

    # The Errors chip narrows the list to errors, under their interaction.
    view |> element(~s(button[phx-click="errors_only"]), "Errors") |> render_click()
    assert has_element?(view, ~s(button[phx-click="errors_only"][aria-pressed="true"]))
    rows = view |> render() |> LazyHTML.from_document() |> LazyHTML.query("#replay-events li li")
    assert [row] = Enum.to_list(rows)
    assert LazyHTML.text(row) =~ "boom"
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
    assert open_tab(view, "State") =~ "count"
    assert has_element?(view, "#replay-assigns summary", "2")
  end

  test "redacts a live session before showing it, and hands it to the frame" do
    buffer_live("live-1")
    html = build_conn() |> get("/replay/live-1") |> html_response(200)
    assert html =~ "Redacting the session"
    refute html =~ "4242"

    {:ok, view, _html} = live(build_conn(), "/replay/live-1")
    channel = assigns(view).channel
    Playback.subscribe(channel)
    Playback.frame_ready(channel)

    assert render_async(view) =~ "PhoenixReplay.Test.Live.Counter"
    assert assigns(view).recording.url == "http://localhost/cards/[REDACTED]"
    assert_receive {Playback, {:load, %{url: "http://localhost/cards/[REDACTED]"}}}
    assert_receive {Playback, {:seek, 1}}
  end

  test "navigates away from live sessions the viewer may not see" do
    buffer_live("secret-live")
    {:ok, view, _html} = live(build_conn(), "/restricted/replay/secret-live")

    assert_redirect(view, "/restricted/replay")
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

  test "plays on after the last event to the end of the pointer track" do
    recording = Fixtures.counter_recording(id: "pointed", clicks: 1)
    last = PhoenixReplay.Recording.Timeline.duration_ms(recording)
    # The pointer moved for three seconds after the last LiveView event.
    batch = %Event{
      at: last + 3_000,
      type: :pointer,
      data: %{span: 100, moves: [100, 5, 5, 0], presses: [], scrolls: []}
    }

    client = %{recording.client | viewport: %{width: 390, height: 844, dpr: 3}}

    Storage.save(Fixtures.storage(), %{
      recording
      | events: [batch | recording.events],
        client: client
    })

    {:ok, view, _html} = live(build_conn(), "/replay/pointed?at=3")
    assert %{index: 3, duration_ms: duration} = assigns(view)
    assert duration == last + 3_000
    assert has_element?(view, "#replay-pointer")

    render_click(view, "toggle")
    assert %{at: ^duration, playing: nil} = advance(view)

    # At the very end, playing starts over.
    render_click(view, "toggle")
    assert %{index: 1} = assigns(view)
    # Events at the same time play on.
    Storage.save(Fixtures.storage(), %{
      recording
      | id: "same",
        events: Enum.map(recording.events, &%{&1 | at: 0})
    })

    {:ok, view, _html} = live(build_conn(), "/replay/same?at=0")
    render_click(view, "toggle")
    assert %{playing: {_timer, _ref}} = advance(view)
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
    view |> element(~s(button[value="10"])) |> render_click()
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

  describe "client context" do
    defp client(viewport, tab, referer \\ nil) do
      %{
        viewport: viewport,
        user_agent: "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) Safari/604.1",
        tab: tab,
        referer: referer
      }
    end

    test "sizes the frame to the recorded viewport and names the device" do
      recording = %{
        Fixtures.counter_recording(id: "phone")
        | client: client(%{width: 390, height: 844, dpr: 3}, nil)
      }

      Storage.save(Fixtures.storage(), recording)
      {:ok, view, _html} = live(build_conn(), "/replay/phone")

      assert has_element?(
               view,
               ~s(#replay-viewport[data-width="390"][data-height="844"][data-mode="fit"])
             )

      view |> element(~s(button[value="actual"])) |> render_click()
      assert has_element?(view, ~s(#replay-viewport[data-mode="actual"]))
      assert has_element?(view, ~s(button[value="actual"][aria-pressed="true"]))
      open_tab(view, "Visit")
      device = view |> element("#replay-device") |> render()
      assert device =~ "390 × 844 @3x"
      assert device =~ "· Mobile Safari on iOS"
    end

    test "shows how the visit started" do
      recording = Fixtures.counter_recording(id: "visit")

      client =
        Map.merge(recording.client, %{
          headers: %{"accept-language" => "de-DE"},
          landing: %{
            path: "/pricing",
            at: 1_700_000_000_000,
            params: %{"utm_source" => "google", "utm_medium" => "cpc"},
            referrer: "https://www.google.com/search"
          }
        })

      Storage.save(Fixtures.storage(), %{recording | client: client})
      {:ok, view, _html} = live(build_conn(), "/replay/visit")
      open_tab(view, "Visit")

      visit = view |> element("#replay-visit") |> render()
      assert visit =~ "google / cpc"
      assert visit =~ "from www.google.com"
      assert visit =~ "/pricing"
      assert visit =~ "de-DE"
    end

    test "links the sessions of one browser tab" do
      for {id, at} <- [{"first", 1}, {"second", 2}, {"third", 3}] do
        referer = if id != "first", do: "http://localhost/counter"
        recording = Fixtures.counter_recording(id: id, connected_at: at)
        Storage.save(Fixtures.storage(), %{recording | client: client(nil, "tab-9", referer)})
      end

      {:ok, view, _html} = live(build_conn(), "/replay/second")

      assert open_tab(view, "Visit") =~ "Came from"
      assert view |> element("#replay-journey") |> render() =~ "Session 2 of 3 in this tab"
      assert has_element?(view, ~s(#replay-journey a[href="/replay/first"]), "Previous")
      assert has_element?(view, ~s(#replay-journey a[href="/replay/third"]), "Next")
      assert has_element?(view, ~s(#replay-journey a[href="/replay?tab=tab-9"]))
    end
  end
end
