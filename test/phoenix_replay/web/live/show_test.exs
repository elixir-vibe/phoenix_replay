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

    assert has_element?(
             view,
             ~s(button[data-copy="/replay/show?at=4&t=2000"]),
             "Copy link to 0:02.00"
           )

    render_click(view, "next")
    assert has_element?(view, ~s(button[data-copy="/replay/show?at=5&t=2001"]))
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
    # Within the assign's row, by the path inside it; the full path on hover.
    assert changes =~ ~s(title="tasks[id: 2].done")
    assert changes =~ ~r/>\s*\[id: 2\]\.done\s*</

    assert changes =~
             ~s(<span class="l-boolean">false</span> → <span class="l-boolean">true</span>)

    diff = view |> element("[data-diff]") |> render()
    assert diff =~ ~s(data-op="del")
    assert diff =~ ~s(data-op="ins")

    # Where the assign first appears, there is nothing to compare it with.
    render_click(view, "seek", %{"index" => "1"})
    refute has_element?(view, "[data-changes]")
  end

  test "shows the value an assign replaced whole, dimmed before its new one" do
    {:ok, view, _html} = live(build_conn(), "/replay/show?at=3")
    open_tab(view, "State")

    assert has_element?(view, ~s([data-assign="count"] [data-was]), "0")
    assert has_element?(view, ~s([data-assign="count"]), ~r/0\s*→\s*1/)
    refute has_element?(view, ~s([data-changes="count"]))
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

  test "links the moment it is at, between events too, to the hundredth of a second" do
    # Between the first render at 5 ms and the click at 1000 ms.
    {:ok, view, _html} = live(build_conn(), "/replay/show?at=1&t=500")

    assert %{index: 1, at: 500} = assigns(view)

    assert has_element?(
             view,
             ~s(button[data-copy="/replay/show?at=1&t=500"]),
             "Copy link to 0:00.50"
           )

    # A time outside the event's span is kept within it.
    {:ok, view, _html} = live(build_conn(), "/replay/show?at=1&t=99999")
    assert %{index: 1, at: 1_000} = assigns(view)
  end

  test "moves by time, to either end and between errors, as its keyboard shortcuts ask" do
    recording = Fixtures.counter_recording(id: "keys")
    error = %Event{at: 1500, type: :log, data: %{level: :error, message: "boom", metadata: %{}}}
    events = recording.events |> List.insert_at(4, error) |> List.insert_at(2, %{error | at: 500})
    Storage.save(Fixtures.storage(), %{recording | events: events})
    {:ok, view, _html} = live(build_conn(), "/replay/keys")
    assert %{index: 1, at: 5} = assigns(view)

    # Five seconds on is past the end; five back is before the first render.
    render_hook(view, "skip", %{"by" => 5_000})
    assert %{index: 7, at: 2_001} = assigns(view)
    render_hook(view, "skip", %{"by" => -1_000})
    assert %{index: 4, at: 1_001} = assigns(view)
    render_hook(view, "skip", %{"by" => -5_000})
    assert %{index: 1, at: 5} = assigns(view)

    render_hook(view, "jump", %{"to" => "end"})
    assert %{index: 7, at: 2_001} = assigns(view)
    render_hook(view, "jump", %{"to" => "start"})
    assert %{index: 1} = assigns(view)

    render_hook(view, "error", %{"direction" => "next"})
    assert assigns(view).index == 2
    render_hook(view, "error", %{"direction" => "next"})
    assert assigns(view).index == 5
    # Past the last error, back to the first, and before it, to the last.
    render_hook(view, "error", %{"direction" => "next"})
    assert assigns(view).index == 2
    render_hook(view, "error", %{"direction" => "previous"})
    assert assigns(view).index == 5
  end

  test "gives marks a lane of their own and jumps between them" do
    recording = Fixtures.counter_recording(id: "marked")

    mark = fn at, summary ->
      %Event{
        at: at,
        type: :telemetry,
        data: %{
          event: [:shop, :step],
          summary: summary,
          measurements: %{duration: 250, amount: 4900},
          metadata: %{},
          error: nil,
          mark: "Step"
        }
      }
    end

    events =
      recording.events
      |> List.insert_at(4, mark.(1_500, "paid"))
      |> List.insert_at(3, mark.(1_000, "carted"))

    Storage.save(Fixtures.storage(), %{recording | events: events})
    {:ok, view, html} = live(build_conn(), "/replay/marked")

    assert html =~ "Marks"
    assert has_element?(view, ~s(button[phx-click="toggle_kind"][phx-value-kind="marks"]))

    # The header lists them, each a jump to its moment.
    assert has_element?(view, "#replay-marks-button", "2 marks")
    assert has_element?(view, "#replay-marks-items button", "Step")
    assert has_element?(view, "#replay-marks-items button", "0:01")

    # Rows name the mark, and slow events stand out.
    assert has_element?(view, "#replay-events button span.text-kind-mark", "Step")
    assert has_element?(view, ~s(#replay-events [title="Slower than 100 ms"]), "250 ms")

    render_hook(view, "mark", %{"direction" => "next"})
    assert assigns(view).index == 3
    assert has_element?(view, "#replay-details", "carted")
    # Measurements other than the duration are shown too.
    assert has_element?(view, "#replay-details dd", "amount: 4900")
    render_hook(view, "mark", %{"direction" => "next"})
    assert assigns(view).index == 5
    render_hook(view, "mark", %{"direction" => "previous"})
    assert assigns(view).index == 3
    render_hook(view, "mark", %{"direction" => "previous"})
    assert assigns(view).index == 5
  end

  test "shows its keyboard shortcuts on its controls and in a sheet" do
    {:ok, view, _html} = live(build_conn(), "/replay/show")

    assert has_element?(view, ~s(#replay-keys[phx-hook="PlayerKeys"][data-shortcuts]))
    assert has_element?(view, ~s(button[aria-label="Play"][aria-keyshortcuts="Space K"]))
    assert has_element?(view, ~s(button[aria-label="Next event"][aria-keyshortcuts="ArrowRight"]))
    assert has_element?(view, ~s(button[value="5"][aria-keyshortcuts="3"]))
    assert has_element?(view, "#replay-event-search kbd", "/")
    # The arrow shows as a glyph and reads as its name.
    assert has_element?(view, "kbd .sr-only", "Right arrow")

    render_hook(view, "toggle_frame_mode", %{})
    assert assigns(view).frame_mode == "actual"
    render_hook(view, "toggle_frame_mode", %{})
    assert assigns(view).frame_mode == "fit"

    view |> element("#replay-shortcuts-button") |> render_click()
    assert has_element?(view, "#replay-shortcuts h3", "Playback")
    assert has_element?(view, "#replay-shortcuts dt", "Back 5 seconds")
    # Letters are capitals on keycaps; named keys stay words.
    assert has_element?(view, "#replay-shortcuts kbd kbd", ~r/^\s*Shift\s*$/)
    assert has_element?(view, "#replay-shortcuts kbd kbd", ~r/^\s*K\s*$/)
    render_hook(view, "close_shortcuts", %{})
    refute has_element?(view, "#replay-shortcuts")
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
    # The mount before the first render has no assigns to render with.
    assert assigns(view).index == 1
    assert has_element?(view, ~s(button[aria-label="Previous event"][disabled]))
    render_hook(view, "seek", %{"index" => 0})
    assert assigns(view).index == 1

    render_hook(view, "seek", %{"index" => 5})
    assert assigns(view).index == 5
    assert open_tab(view, "State") =~ "count"
    assert has_element?(view, ~s(#replay-assigns [data-assign="count"]), "2")
  end

  test "redacts a live session before showing it, and hands it to the frame" do
    buffer_live("live-1")
    html = build_conn() |> get("/replay/live-1") |> html_response(200)
    assert html =~ "Redacting the recording"
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

      # Turned to look at it, the page keeps its layout, so it still follows.
      view |> element("#replay-follow-scroll") |> render_click()
      view |> element("#replay-rotate") |> render_click()
      refute has_element?(view, "#replay-follow-scroll[disabled]")
      assert has_element?(view, "#replay-frame.pointer-events-none")

      # A recording without scrolling has nothing to follow.
      {:ok, view, _html} = live(build_conn(), "/replay/show")
      refute has_element?(view, "#replay-follow-scroll")
      refute has_element?(view, "#replay-frame.pointer-events-none")
    end

    test "turns the shown device to look at it, keeping the recorded page and pointer" do
      recording = Fixtures.counter_recording(id: "turned")

      pointer = %Event{
        at: 0,
        type: :pointer,
        data: %{span: 100, moves: [100, 5, 5, 0], presses: [], scrolls: []}
      }

      landscape = %Event{
        at: PhoenixReplay.Recording.Timeline.duration_ms(recording) + 1,
        type: :viewport,
        data: %{width: 844, height: 390, dpr: 3, angle: 90}
      }

      Storage.save(Fixtures.storage(), %{
        recording
        | client: client(%{width: 390, height: 844, dpr: 3, angle: 0}, nil),
          events: [pointer | recording.events] ++ [landscape]
      })

      {:ok, view, _html} = live(build_conn(), "/replay/turned")
      refute has_element?(view, "#replay-viewport[data-turn]")

      view |> element("#replay-rotate") |> render_click()
      assert has_element?(view, ~s(#replay-rotate[aria-checked="true"]))
      assert has_element?(view, "#replay-viewport[data-turn]")
      # The page keeps its recorded viewport, and the pointer stays.
      assert has_element?(view, ~s(#replay-viewport[data-width="390"][data-height="844"]))
      refute has_element?(view, "#replay-pointer-switch[disabled]")

      # When the recording turns, the device turns back with it.
      render_click(view, "seek", %{"index" => length(recording.events) + 1})
      assert has_element?(view, ~s(#replay-viewport[data-width="844"][data-angle="90"]))
      refute has_element?(view, "#replay-viewport[data-turn]")
      assert has_element?(view, ~s(#replay-rotate[aria-checked="false"]))
    end

    test "notes the assigns a recording lacks, which the frame shows unset" do
      Storage.save(Fixtures.storage(), Fixtures.counter_recording(id: "older"))
      {:ok, view, _html} = live(build_conn(), "/replay/older")
      refute has_element?(view, "#replay-unrecorded")

      send(view.pid, {PhoenixReplay.Web.Player.Channel, {:unrecorded, [:theme, :plan]}})
      assert has_element?(view, "#replay-unrecorded", "Not in recording: @theme, @plan")
    end

    test "replays the color scheme the user had" do
      recording = Fixtures.counter_recording(id: "dark")

      Storage.save(Fixtures.storage(), %{
        recording
        | client:
            client(
              %{width: 390, height: 844, dpr: 3, color_scheme: :dark, pointer: :coarse},
              nil
            )
      })

      {:ok, view, _html} = live(build_conn(), "/replay/dark")

      assert has_element?(
               view,
               ~s(#replay-frame[data-media='{"pointer":"coarse","prefers-color-scheme":"dark"}'])
             )

      assert has_element?(view, ~s(#replay-frame[style="color-scheme: dark"]))

      open_tab(view, "Visit")
      assert has_element?(view, "#replay-settings", "Dark theme · Touch screen")
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
      # Each links to the recordings that came the same way.
      assert has_element?(
               view,
               ~s(#replay-visit-campaign[href="/replay?medium=cpc&source=google"])
             )

      assert has_element?(view, ~s(#replay-visit a[href="/replay?source=www.google.com"]))
      assert visit =~ "/pricing"
      assert visit =~ "de-DE"

      # Each value is as recorded, without the template's line breaks, which
      # the list would keep.
      values =
        visit |> LazyHTML.from_fragment() |> LazyHTML.query("dd") |> Enum.map(&LazyHTML.text/1)

      assert "cpc" in values
      assert "google" in values
    end

    test "lists the pages of the visit, each opening its page" do
      save_visit([{"first", 1}, {"second", 5_000}, {"third", 9_000}])
      {:ok, view, _html} = live(build_conn(), "/replay/second")

      assert view |> element("#replay-pages") |> render() =~ "page 2 of 3"
      assert has_element?(view, ~s(#replay-page-second[aria-current="page"]))

      open_tab(view, "Visit")
      assert view |> element("#replay-visit-pages") |> render() =~ "/counter"

      view |> element(~s(#replay-visit-pages button[phx-value-id="third"])) |> render_click()
      assert has_element?(view, ~s(#replay-page-third[aria-current="page"]))
      assert view |> element("#replay-pages") |> render() =~ "page 3 of 3"
    end

    test "seeks on the visit's clock, to the page open then and the moment in it" do
      save_visit([{"first", 1}, {"second", 5_000}, {"third", 9_000}])
      {:ok, view, _html} = live(build_conn(), "/replay/first")

      # 1 s into the second page, which started 4999 ms into the visit.
      render_click(view, "visit_seek", %{"at" => 5_999})
      assert has_element?(view, ~s(#replay-page-second[aria-current="page"]))
      assert has_element?(view, ~s(#replay-visit-timeline[aria-valuenow="5999"]))

      # Between pages, the next one, from its first render, 5 ms in.
      render_click(view, "visit_seek", %{"at" => 8_000})
      assert has_element?(view, ~s(#replay-page-third[aria-current="page"]))
      assert has_element?(view, ~s(#replay-visit-timeline[aria-valuenow="9004"]))
    end

    test "marks the errors of every page on the visit's timeline" do
      error = %Event{at: 1_500, type: :log, data: %{level: :error, message: "x", metadata: %{}}}

      for {id, at, extra} <- [{"first", 1, []}, {"second", 5_000, [error]}] do
        recording = Fixtures.counter_recording(id: id, connected_at: at)

        Storage.save(Fixtures.storage(), %{
          recording
          | events: recording.events ++ extra,
            client: %Client{visit: "visit-9"}
        })
      end

      {:ok, view, _html} = live(build_conn(), "/replay/first")
      assert has_element?(view, ~s(#replay-visit-timeline [data-marker="error"]))
    end
  end

  describe "a visit" do
    test "plays on from one page to the next" do
      # The second page opened while the first was still open, so it follows at once.
      save_visit([{"first", 1}, {"second", 1_500}])
      {:ok, view, _html} = live(build_conn(), "/replay/first")

      render_click(view, "speed", %{"value" => "10"})
      render_click(view, "toggle")

      assert eventually(fn ->
               has_element?(view, ~s(#replay-page-second[aria-current="page"]))
             end)

      assert view |> element("#replay-pages") |> render() =~ "page 2 of 2"
    end

    test "stops at the end of a page rather than go back to a tab closed while it played" do
      # The second tab opened at 1 s and closed at 3 s, while the first page ran to 4 s.
      for {id, at, clicks} <- [{"long", 1, 4}, {"tab", 1_001, 2}] do
        recording = Fixtures.counter_recording(id: id, connected_at: at, clicks: clicks)
        Storage.save(Fixtures.storage(), %{recording | client: %Client{visit: "visit-9"}})
      end

      {:ok, view, _html} = live(build_conn(), "/replay/long")
      render_click(view, "speed", %{"value" => "10"})
      render_click(view, "toggle")

      assert eventually(fn -> has_element?(view, ~s(button[aria-label="Play"])) end)
      assert has_element?(view, ~s(#replay-page-long[aria-current="page"]))
    end

    test "opens a page still recording, from a saved page of the visit" do
      save_visit([{"saved", 1}])

      running = %{
        Fixtures.counter_recording(id: "running", connected_at: 9_000)
        | client: %Client{visit: "visit-9"}
      }

      :ok = Buffer.open(running, self(), Config.load())

      running.events
      |> Enum.with_index()
      |> Enum.each(fn {event, seq} -> Buffer.append("running", seq, event) end)

      on_exit(fn -> Buffer.close("running") end)

      {:ok, view, _html} = live(build_conn(), "/replay/saved")
      assert view |> element("#replay-pages") |> render() =~ "page 1 of 2"

      open_tab(view, "Visit")
      view |> element(~s(#replay-visit-pages button[phx-value-id="running"])) |> render_click()
      assert has_element?(view, ~s(#replay-page-running[aria-current="page"]))
    end
  end

  defp save_visit(pages) do
    for {id, at} <- pages do
      recording = Fixtures.counter_recording(id: id, connected_at: at)
      Storage.save(Fixtures.storage(), %{recording | client: %Client{visit: "visit-9"}})
    end
  end

  # Playback runs on timers; this waits for it, bounded.
  defp eventually(check, tries \\ 100) do
    cond do
      check.() ->
        true

      tries == 0 ->
        false

      true ->
        Process.sleep(20)
        eventually(check, tries - 1)
    end
  end
end
