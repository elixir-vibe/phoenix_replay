defmodule PhoenixReplay.Web.Live.ShowTest do
  use ExUnit.Case, async: false

  import Phoenix.ConnTest
  import Phoenix.LiveViewTest

  alias PhoenixReplay.{Config, Storage}
  alias PhoenixReplay.Recording.{Client, Event}
  alias PhoenixReplay.Recording.Client.Landing
  alias PhoenixReplay.Session.Buffer
  alias PhoenixReplay.Test.Fixtures
  alias PhoenixReplay.Web.Player.Channel

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

  # Waits for playback to stop by itself.
  defp played(view, tries \\ 50) do
    case assigns(view) do
      %{playing: nil} = assigns ->
        assigns

      _playing when tries > 0 ->
        Process.sleep(10)
        played(view, tries - 1)

      assigns ->
        assigns
    end
  end

  # Delivers the pending playback step now. Playback tests use recordings
  # with hour-long gaps, so the real timer cannot fire during the test.
  defp advance(view) do
    %{playing: %{timer: timer, ref: ref}} = assigns(view)
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
    assert has_element?(view, ~s(#replay-assigns [data-assign="count"].bg-accent-soft))
  end

  test "expands only values its row cannot show whole, and offers a theme switch" do
    recording = Fixtures.counter_recording(id: "values", clicks: 1)
    long = Enum.to_list(1..30)

    render = %Event{
      at: 5,
      type: :render,
      data: %{assigns: %{count: 0, items: long, note: "short"}}
    }

    Storage.save(Fixtures.storage(), %{recording | events: [hd(recording.events), render]})

    {:ok, view, _html} = live(build_conn(), "/replay/values?at=1")
    open_tab(view, "State")

    assert has_element?(view, ~s(#replay-assigns div[data-assign="count"]))
    assert has_element?(view, ~s(#replay-assigns div[data-assign="note"]))
    assert has_element?(view, ~s(#replay-assigns details summary [data-assign="items"]))
    assert has_element?(view, ~s(#replay-assigns span.l-number), "0")
    assert has_element?(view, "#theme-toggle[data-theme-toggle]")
  end

  test "shows what an event changed inside an assign, and the whole value with changes marked" do
    recording = Fixtures.counter_recording(id: "changed", clicks: 1)
    tasks = for id <- 1..3, do: %{id: id, title: "Task #{id}", done: false}
    done = List.update_at(tasks, 1, &%{&1 | done: true})

    events = [
      hd(recording.events),
      %Event{at: 5, type: :render, data: %{assigns: %{tasks: tasks, count: 0}}},
      %Event{at: 9, type: :event, data: %{name: "toggle", params: %{"id" => "2"}}},
      %Event{at: 10, type: :render, data: %{assigns: %{tasks: done}}}
    ]

    Storage.save(Fixtures.storage(), %{recording | events: events})
    {:ok, view, _html} = live(build_conn(), "/replay/changed?at=3")
    open_tab(view, "State")

    changes = view |> element(~s([data-changes="tasks"])) |> render()
    assert changes =~ "tasks[id: 2].done"

    assert changes =~
             ~s(<span class="l-boolean">false</span> → <span class="l-boolean">true</span>)

    diff = view |> element("[data-diff]") |> render()
    assert diff =~ ~s(data-op="del")
    assert diff =~ ~s(data-op="ins")

    # Where the assign first appears, there is nothing to compare it with.
    render_click(view, "seek", %{"index" => "1"})
    refute has_element?(view, "[data-changes]")
  end

  test "lists client state in a lane of its own, as steps" do
    recording = Fixtures.counter_recording(id: "stateful", clicks: 1)
    inputs = PhoenixReplay.Recording.State.inputs_key()

    typed = %Event{
      at: 3_000,
      type: :state,
      data: %{
        span: 100,
        entries: [
          [0, inputs, %{"#note" => %{"note" => "call"}}],
          [100, "search", %{"query" => "x"}]
        ]
      }
    }

    Storage.save(Fixtures.storage(), %{recording | events: [typed | recording.events]})
    {:ok, view, _html} = live(build_conn(), "/replay/stateful")

    assert has_element?(view, "#replay-events", ~s(input #note "call"))
    assert has_element?(view, "#replay-events", ~s(search: query "x"))
    assert has_element?(view, ~s(button[phx-value-kind="state"]), "Client state")
  end

  test "loads the frame once, when the player has connected" do
    # The first render is not connected: a frame address there would load
    # the frame, then again with the connected player's channel.
    html = build_conn() |> get("/replay/show") |> html_response(200)

    [frame] =
      html |> LazyHTML.from_document() |> LazyHTML.query("#replay-frame") |> Enum.to_list()

    assert LazyHTML.attribute(frame, "src") == []

    {:ok, view, _html} = live(build_conn(), "/replay/show")
    assert has_element?(view, ~s(#replay-frame[src^="/replay/show/frame?channel="]))
  end

  test "jumps to the first error" do
    recording = Fixtures.counter_recording(id: "failing")
    error = %Event{at: 1500, type: :log, data: %{level: :error, message: "boom", metadata: %{}}}
    events = List.insert_at(recording.events, 4, error)
    Storage.save(Fixtures.storage(), %{recording | events: events})

    {:ok, view, _html} = live(build_conn(), "/replay/failing")
    view |> element("button", "1 error · jump to first") |> render_click()

    assert assigns(view).index == 4
    # Its details are in the pane, not under its row.
    assert has_element?(view, ~s(#replay-details[data-index="4"] dd), "boom")
    refute has_element?(view, "#replay-events dd")

    # Pinned, they stay while the player moves on; unpinned, they follow it.
    view |> element("#replay-details-pin") |> render_click()
    assert has_element?(view, ~s(#replay-details-pin[aria-pressed="true"]))
    render_click(view, "seek", %{"index" => "2"})
    assert has_element?(view, ~s(#replay-details[data-index="4"]))
    view |> element("#replay-details-pin") |> render_click()
    assert has_element?(view, ~s(#replay-details[data-index="2"]), "inc")

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
    assert has_element?(view, ~s(#replay-assigns [data-assign="count"]), "2")
  end

  test "redacts a live session before showing it, and hands it to the frame" do
    buffer_live("live-1")
    html = build_conn() |> get("/replay/live-1") |> html_response(200)
    assert html =~ "Redacting the session"
    refute html =~ "4242"

    {:ok, view, _html} = live(build_conn(), "/replay/live-1")
    channel = assigns(view).channel
    Channel.subscribe(channel)
    Channel.frame_ready(channel)

    assert render_async(view) =~ "PhoenixReplay.Test.Live.Counter"
    assert assigns(view).recording.url == "http://localhost/cards/[REDACTED]"
    assert_receive {Channel, {:load, %{url: "http://localhost/cards/[REDACTED]"}}}
    assert_receive {Channel, {:seek, 1}}
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

    Channel.subscribe(channel)
    render_hook(view, "seek", %{"index" => "3"})
    assert_receive {Channel, {:seek, 3}}

    Channel.frame_ready(channel)
    assert_receive {Channel, {:seek, 3}}
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
    assert has_element?(view, ~s(#replay-pointer-switch[role="switch"][aria-checked="true"]))

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

    # With no gaps the real timers play it at once: through every event,
    # not stopping at the first that shares its time.
    {:ok, view, _html} = live(build_conn(), "/replay/same?at=0")
    render_click(view, "toggle")
    assert %{index: 3, playing: nil} = played(view)
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
    assert %{playing: %{timer: timer}} = assigns(view)
    assert Process.read_timer(timer) in (div(gap, 10) - 1_000)..div(gap, 10)

    assert [2, 3, 4, 5] = for(_ <- 1..4, do: advance(view).index)
    assert %{index: 5, playing: nil} = assigns(view)

    render_click(view, "toggle")
    assert %{index: 1} = assigns(view)
    render_click(view, "toggle")
    assert %{playing: nil} = assigns(view)
  end

  test "pausing keeps the time playback reached, and resuming plays on from it" do
    gap = :timer.hours(1)
    recording = Fixtures.counter_recording(id: "paused", clicks: 2)

    events =
      recording.events
      |> Enum.with_index()
      |> Enum.map(fn {event, i} -> %{event | at: i * gap} end)

    Storage.save(Fixtures.storage(), %{recording | events: events})
    {:ok, view, _html} = live(build_conn(), "/replay/paused")
    view |> element(~s(button[value="10"])) |> render_click()
    %{index: index, at: start} = assigns(view)

    render_click(view, "toggle")
    Process.sleep(100)
    render_click(view, "toggle")

    # A tenth of a second at 10x is a second into the gap, not back at its event.
    assert %{index: ^index, at: paused, playing: nil} = assigns(view)
    assert paused in (start + 1_000)..(start + 10_000)
    assert view |> element("#replay-scrubber") |> render() =~ ~s(data-at="#{paused}")

    # Resuming waits only for what is left of the gap.
    render_click(view, "toggle")
    assert %{playing: %{timer: timer}} = assigns(view)
    assert Process.read_timer(timer) <= div(start + gap - paused, 10)

    # Changing speed while playing keeps the time too.
    Process.sleep(50)
    view |> element(~s(button[value="2"])) |> render_click()
    assert %{at: at, playing: %{}} = assigns(view)
    assert at > paused

    render_click(view, "toggle")
    assert %{at: stopped} = assigns(view)
    assert stopped >= at
  end

  test "seeks to the time the scrubber was let go at, between events" do
    gap = :timer.hours(1)
    recording = Fixtures.counter_recording(id: "scrubbed", clicks: 2)

    events =
      recording.events
      |> Enum.with_index()
      |> Enum.map(fn {event, i} -> %{event | at: i * gap} end)

    Storage.save(Fixtures.storage(), %{recording | events: events})
    {:ok, view, _html} = live(build_conn(), "/replay/scrubbed")

    # Halfway into the gap after event 2, not snapped back to it.
    render_click(view, "seek", %{"index" => 2, "at" => 2 * gap + div(gap, 2)})
    assert %{index: 2, at: at} = assigns(view)
    assert at == 2 * gap + div(gap, 2)

    # A time outside the event's gap is held to it.
    render_click(view, "seek", %{"index" => 2, "at" => 10 * gap})
    assert %{at: at} = assigns(view)
    assert at == 3 * gap

    # Choosing an event, as the event list does, goes to its time.
    render_click(view, "seek", %{"index" => 1})
    assert %{index: 1, at: ^gap} = assigns(view)
  end

  test "covers the frame with a loader until its LiveView connects" do
    {:ok, view, _html} = live(build_conn(), "/replay/show")
    assert has_element?(view, ~s(#replay-loading[data-ready="false"]))

    send(view.pid, {Channel, :frame_ready})
    assert has_element?(view, ~s(#replay-loading[data-ready="true"]))
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

  test "follows an export of the recording and links its video", %{recording: recording} do
    {:ok, view, _html} = live(build_conn(), "/replay/show")
    refute has_element?(view, "#replay-export-status")
    job = %PhoenixReplay.Export.Job{id: "j", recording_id: recording.id, options: nil}

    send(view.pid, {PhoenixReplay.Export, %{job | status: :running, progress: 42}})
    assert has_element?(view, ~s(#replay-export-status [role="progressbar"][aria-valuenow="42"]))
    # Cancelling asks the server; its answer arrives as the job's next state.
    view |> element("#replay-export-cancel") |> render_click()

    send(view.pid, {PhoenixReplay.Export, %{job | status: :cancelling}})
    assert has_element?(view, "#replay-export-status", "Cancelling the export")
    refute has_element?(view, "#replay-export-cancel")

    send(view.pid, {PhoenixReplay.Export, %{job | status: :cancelled}})
    assert has_element?(view, "#replay-export-status", "Export cancelled")

    send(
      view.pid,
      {PhoenixReplay.Export, %{job | status: :done, progress: 100, path: "/tmp/j.mp4"}}
    )

    assert has_element?(view, ~s(#replay-export-download[href^="/replay/show/video/"]))

    send(view.pid, {PhoenixReplay.Export, %{job | status: :failed, error: "The browser failed."}})
    assert has_element?(view, "#replay-export-status", "The browser failed.")
    view |> element(~s(#replay-export-status button[aria-label="Dismiss"])) |> render_click()
    refute has_element?(view, "#replay-export-status")

    # Another recording's exports are not shown.
    send(view.pid, {PhoenixReplay.Export, %{job | recording_id: "other"}})
    refute has_element?(view, "#replay-export-status")
  end

  describe "client context" do
    defp client(viewport, tab, navigated_from \\ nil) do
      %Client{
        viewport: viewport,
        user_agent: "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) Safari/604.1",
        tab: tab,
        navigated_from: navigated_from
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

      view |> element(~s(#replay-view-items button[value="actual"])) |> render_click()
      assert has_element?(view, ~s(#replay-viewport[data-mode="actual"]))
      assert has_element?(view, ~s(button[value="actual"][aria-checked="true"]))
      open_tab(view, "Visit")
      device = view |> element("#replay-device") |> render()
      assert device =~ "390 × 844 @3x"
      assert device =~ "· Mobile Safari on iOS"
    end

    test "shows whether the viewport is portrait or landscape at each moment" do
      recording = Fixtures.counter_recording(id: "rotated")

      rotated = %Event{
        at: PhoenixReplay.Recording.Timeline.duration_ms(recording) + 1,
        type: :viewport,
        data: %{width: 844, height: 390, dpr: 3}
      }

      Storage.save(Fixtures.storage(), %{
        recording
        | client: client(%{width: 390, height: 844, dpr: 3}, nil),
          events: List.insert_at(recording.events, -1, rotated)
      })

      {:ok, view, _html} = live(build_conn(), "/replay/rotated?at=0")
      assert has_element?(view, ~s(#replay-orientation[data-orientation="portrait"]), "portrait")

      render_click(view, "seek", %{"index" => length(recording.events)})
      assert has_element?(view, ~s(#replay-viewport[data-width="844"][data-height="390"]))
      assert has_element?(view, ~s(#replay-orientation[data-orientation="landscape"]))
      assert render(view) =~ "landscape"
    end

    test "holds the page where the user scrolled, unless told not to" do
      recording = Fixtures.counter_recording(id: "scrolled")

      scrolled = %Event{
        at: 1_500,
        type: :pointer,
        data: %{span: 100, moves: [], presses: [], scrolls: [50, 0, 300]}
      }

      Storage.save(Fixtures.storage(), %{
        recording
        | client: client(%{width: 390, height: 844, dpr: 3}, nil),
          events: List.insert_at(recording.events, 4, scrolled)
      })

      {:ok, view, _html} = live(build_conn(), "/replay/scrolled")
      assert has_element?(view, ~s(#replay-follow-scroll[aria-checked="true"]))
      assert has_element?(view, "#replay-frame.pointer-events-none")
      assert has_element?(view, "#replay-pointer[data-follow-scroll]")

      view |> element("#replay-follow-scroll") |> render_click()
      assert has_element?(view, ~s(#replay-follow-scroll[aria-checked="false"]))
      refute has_element?(view, "#replay-frame.pointer-events-none")
      refute has_element?(view, "#replay-pointer[data-follow-scroll]")

      # Rotated, the recorded positions do not fit, so the page scrolls freely.
      view |> element("#replay-follow-scroll") |> render_click()
      view |> element("#replay-rotate") |> render_click()
      assert has_element?(view, "#replay-follow-scroll[disabled]")
      refute has_element?(view, "#replay-frame.pointer-events-none")

      # A recording without scrolling has nothing to follow.
      {:ok, view, _html} = live(build_conn(), "/replay/show")
      refute has_element?(view, "#replay-follow-scroll")
      refute has_element?(view, "#replay-frame.pointer-events-none")
    end

    test "rotates the replay to the other orientation, without the pointer" do
      recording = Fixtures.counter_recording(id: "turned")

      pointer = %Event{
        at: 0,
        type: :pointer,
        data: %{span: 100, moves: [100, 5, 5, 0], presses: [], scrolls: []}
      }

      Storage.save(Fixtures.storage(), %{
        recording
        | client: client(%{width: 390, height: 844, dpr: 3}, nil),
          events: [pointer | recording.events]
      })

      {:ok, view, _html} = live(build_conn(), "/replay/turned")
      refute has_element?(view, "#replay-pointer-switch[disabled]")

      view |> element("#replay-rotate") |> render_click()
      assert has_element?(view, ~s(#replay-rotate[aria-checked="true"]))
      assert has_element?(view, ~s(#replay-viewport[data-width="844"][data-height="390"]))
      assert has_element?(view, ~s(#replay-orientation[data-orientation="landscape"]))
      assert has_element?(view, "#replay-pointer-switch[disabled]")
      assert has_element?(view, "#replay-pointer[data-rotated]")

      view |> element("#replay-rotate") |> render_click()
      assert has_element?(view, ~s(#replay-viewport[data-width="390"][data-height="844"]))
      refute has_element?(view, "#replay-pointer[data-rotated]")
    end

    test "shows how the visit started" do
      recording = Fixtures.counter_recording(id: "visit")

      client = %{
        recording.client
        | headers: %{"accept-language" => "de-DE"},
          landing: %Landing{
            path: "/pricing",
            at: 1_700_000_000_000,
            params: %{"utm_source" => "google", "utm_medium" => "cpc"},
            referrer: "https://www.google.com/search"
          }
      }

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
        navigated_from = if id != "first", do: "http://localhost/counter"
        recording = Fixtures.counter_recording(id: id, connected_at: at)

        Storage.save(Fixtures.storage(), %{
          recording
          | client: client(nil, "tab-9", navigated_from)
        })
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
