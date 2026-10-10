defmodule PhoenixReplay.Web.Live.Show do
  @moduledoc """
  Plays back a visit, from the page of the recording it opens with.

  Playback is driven by the server: each step schedules the next one after
  the recorded gap divided by the speed, and tells the frame which event to
  show through `PhoenixReplay.Web.Player.Channel`. At the end of a page,
  playback waits out the time until the visit's next page started, divided
  by the speed, and hands the frame that page's recording; see
  `PhoenixReplay.Web.Player.Pages`. The scrubber, the event list and the
  pointer, client state and marks are the page's. The `Scrubber` hook only maps
  pointer positions to events and animates the thumb between them.

  A session that is still running is redacted before it is shown, which
  can take a while with a detecting `PhoenixReplay.Redactor`. The player
  then loads it with `start_async/3`, shows the redaction's progress, and
  hands the redacted recording to its frame, so the frame never reads the
  buffer itself. Stored recordings were redacted when they were saved and
  load at once.

  Collected telemetry and log events follow the LiveView event that caused
  them, indented, and can be hidden by kind. They leave the replayed state
  as it was, so selecting one shows its details next to the assigns.

  A saved recording can be exported as a video when `PhoenixReplay.Export`
  is available, with the options its dialog offers. The export runs under
  `PhoenixReplay.Export.Queue`, and the player follows its progress and
  links the video when it is ready.
  """

  use Phoenix.LiveView

  import PhoenixIconify, only: [icon: 1]
  import PhoenixReplay.Web.Components.{Export, Layout, State}
  import PhoenixReplay.Web.Components.Player.{EventList, Frame, Header, Pages, Playback, Visit}

  alias PhoenixReplay.Recording.{Client, Event, Filter, PointerTrack, Timeline}
  alias PhoenixReplay.{Catalog, Export, Migration}
  alias PhoenixReplay.Export.Options
  alias PhoenixReplay.Web.{Context, Highlight, Layouts, Params}
  alias PhoenixReplay.Web.Export.Download
  alias PhoenixReplay.Web.Player.{Channel, Events, Pages, Shortcuts}

  @speeds [1, 2, 5, 10]
  # The most sessions of one browser tab the player links between.
  @progress_every 25

  @impl true
  def mount(%{"id" => id} = params, _session, socket) do
    :ok = Highlight.warm()
    context = Context.fetch(socket)
    channel = Channel.new()
    if connected?(socket), do: Channel.subscribe(channel)

    socket =
      assign(socket,
        page_title: "Replay",
        assets: Layouts.dashboard_assets(context),
        context: context,
        id: id,
        # The recording the frame opened with; it is handed any other.
        frame_id: id,
        recording: nil,
        pages: nil,
        # The page playback waits to go on to, between pages.
        gap: nil,
        first_render: 0,
        live?: Catalog.live?(id),
        frame_ready?: false,
        # Assigns the frame's template reads that the recording lacks.
        unrecorded: [],
        progress: nil,
        load_error?: false,
        channel: channel,
        connected?: connected?(socket),
        speed: 1,
        playing: nil,
        speeds: @speeds,
        hidden: MapSet.new(),
        query: "",
        errors_only: false,
        tab: "events",
        frame_mode: "fit",
        # Shows the replay turned to the other orientation than recorded.
        rotated?: false,
        # Holds the frame where the user had scrolled; off, it scrolls freely.
        follow_scroll?: true,
        export: nil,
        exportable?: false,
        # The event the details pane holds while playback goes on, if pinned.
        pinned: nil,
        # The export dialog's params and error while it is open.
        export_dialog: nil,
        # The keyboard shortcut sheet, opened with ?.
        shortcuts?: false,
        # A link to a moment opens the player there.
        start_at: Params.integer(params["at"], nil),
        # And the time there, which may fall between that event and the next.
        start_time: params["t"]
      )

    cond do
      not socket.assigns.live? ->
        {:ok, socket |> loaded(Context.fetch_recording!(socket, id)) |> follow_export()}

      connected?(socket) ->
        {:ok, load_live(socket)}

      true ->
        {:ok, socket}
    end
  end

  defp details_event(%{timeline: %{events: events}, index: index, pinned: pinned})
       when tuple_size(events) > 0 do
    shown = pinned || index
    {elem(events, shown), shown}
  end

  defp details_event(_assigns), do: nil

  defp start_export(socket, options) do
    case Export.start(socket.assigns.id, socket.assigns.context.config, options) do
      {:ok, job} -> assign(socket, :export, job)
      {:error, reason} -> put_flash(socket, :error, Export.describe(reason))
    end
  end

  # Only saved recordings are exported.
  defp follow_export(socket) do
    %{context: context, id: id} = socket.assigns
    exportable? = Export.available?(context.config)
    if connected?(socket) and exportable?, do: Export.subscribe(id)

    assign(socket,
      exportable?: exportable?,
      export: if(connected?(socket) and exportable?, do: Export.latest(id))
    )
  end

  defp load_live(socket) do
    %{context: context, id: id} = socket.assigns
    player = self()

    socket
    |> assign(:progress, {0, 0})
    |> start_async(:recording, fn ->
      Catalog.fetch(context.config, id, progress: &report_progress(player, &1, &2))
    end)
  end

  defp report_progress(player, done, total) when done == total or rem(done, @progress_every) == 0,
    do: send(player, {:redaction_progress, done, total})

  defp report_progress(_player, _done, _total), do: :ok

  defp loaded(socket, recording) do
    # Stepping and seeking follow LiveView events; the overlay plays the
    # pointer track against the same clock.
    {recording, pointer} = Timeline.for_playback(recording)

    socket
    |> assign(
      page_title: "Replay · #{inspect(recording.view)}",
      recording: recording,
      timeline: Timeline.new(recording),
      pointer: pointer,
      progress: nil,
      # The pointer can move on after the last LiveView event.
      duration_ms: max(Timeline.duration_ms(recording), PointerTrack.end_at(pointer)),
      error_count: Events.error_count(recording),
      interactions: Timeline.interactions(recording.events),
      kinds: Events.kinds(recording),
      kind_counts: Events.kind_counts(recording),
      first_error: Events.first_error_index(recording),
      # Events before the first render have no assigns to render the view
      # with, so the player never goes before it.
      first_render: Timeline.first_render_index(recording),
      marks: Events.marks(recording),
      dropped: Events.dropped_count(recording),
      pages: Pages.of(socket, recording),
      code_changes: PhoenixReplay.Recording.Code.changes(recording.code),
      migrations: migrations_applied(recording)
    )
    |> hand_over()
    |> filter_events()
    |> seek(socket.assigns.start_at || 0)
    |> at_time(socket.assigns.start_time)
  end

  # A live session's frame waits for the redacted recording from the
  # player, and a frame shows another page of the visit when handed it.
  defp hand_over(%{assigns: %{frame_ready?: true} = assigns} = socket)
       when assigns.live? or assigns.id != assigns.frame_id do
    :ok = Channel.load(socket.assigns.channel, socket.assigns.recording)
    socket
  end

  defp hand_over(socket), do: socket

  # Opens another page of the visit, at its start or `at` milliseconds in.
  defp switch_page(socket, id, at \\ 0) do
    %{context: context} = socket.assigns

    with {:ok, recording} <- Catalog.fetch(context.config, id),
         true <- Context.allowed?(socket, :view, recording) do
      socket
      |> assign(id: id, live?: Catalog.live?(id), start_at: nil, start_time: nil, gap: nil)
      |> assign(pinned: nil, unrecorded: [], export: nil)
      |> loaded(recording)
      |> then(&if(&1.assigns.live?, do: &1, else: follow_export(&1)))
      |> then(&if(at > 0, do: seek_time(&1, at), else: &1))
    else
      _missing -> put_flash(socket, :error, "That page of the visit could not be opened")
    end
  end

  # At the end of a page, playback follows the visit's clock: on in a tab
  # still open then, or to the next page after the time between them; with
  # neither, it stops. See `Pages.after_page/2`.
  defp end_of_page(%{assigns: %{pages: %{} = pages}} = socket) do
    %{recording: recording, speed: speed} = socket.assigns

    case Pages.after_page(pages, recording.id) do
      {:continue, page, at} ->
        socket |> assign(playing: nil) |> switch_page(page.id, at) |> play()

      {:wait, page, gap} ->
        ref = make_ref()
        timer = Process.send_after(self(), {:next_page, ref, page.id}, div(gap, speed))

        assign(socket,
          playing: %{timer: timer, ref: ref, since: now()},
          gap: %{page: page, ms: gap}
        )

      nil ->
        assign(socket, :playing, nil)
    end
  end

  defp end_of_page(socket), do: assign(socket, :playing, nil)

  # The moment `at` milliseconds into the page, between events if need be.
  defp seek_time(socket, at),
    do: socket |> seek(Timeline.index_at(socket.assigns.recording, at)) |> at_time(at)

  @impl true
  def handle_async(:recording, {:ok, {:ok, recording}}, socket) do
    if Context.allowed?(socket, :view, recording),
      do: {:noreply, loaded(socket, recording)},
      else: {:noreply, not_found(socket)}
  end

  def handle_async(:recording, {:ok, {:error, :not_found}}, socket),
    do: {:noreply, not_found(socket)}

  def handle_async(:recording, _failed, socket),
    do: {:noreply, assign(socket, progress: nil, load_error?: true)}

  # Missing and forbidden recordings look the same, as for stored ones.
  defp not_found(socket) do
    socket
    |> put_flash(:error, "Recording not found")
    |> push_navigate(to: Context.path(socket.assigns.context, []))
  end

  @impl true
  # The scrubber also sends the time it was let go at, which may fall
  # between the event and the next one.
  def handle_event("seek", %{"index" => index} = params, socket) do
    socket = socket |> pause() |> seek(Params.integer(index, socket.assigns.index))
    {:noreply, at_time(socket, params["at"])}
  end

  def handle_event("previous", _params, socket) do
    {:noreply, socket |> pause() |> seek(socket.assigns.index - 1)}
  end

  def handle_event("next", _params, socket) do
    {:noreply, socket |> pause() |> seek(socket.assigns.index + 1)}
  end

  def handle_event("toggle", _params, %{assigns: %{playing: nil}} = socket) do
    {:noreply, play(socket)}
  end

  def handle_event("toggle", _params, socket), do: {:noreply, pause(socket)}

  def handle_event("speed", %{"value" => speed}, socket) do
    speed = Params.integer(speed, 1)
    speed = if speed in @speeds, do: speed, else: 1
    socket = assign(socket, :speed, speed)
    {:noreply, if(socket.assigns.playing, do: socket |> pause() |> play(), else: socket)}
  end

  def handle_event("frame_mode", %{"value" => mode}, socket) when mode in ~w(fit actual) do
    {:noreply, assign(socket, :frame_mode, mode)}
  end

  def handle_event("toggle_frame_mode", _params, socket),
    do: {:noreply, update(socket, :frame_mode, &if(&1 == "fit", do: "actual", else: "fit"))}

  # Moves by time, landing between events as the scrubber can.
  def handle_event("skip", %{"by" => by}, %{assigns: %{recording: %{}}} = socket)
      when is_integer(by) do
    time = (socket.assigns.at + by) |> max(0) |> min(socket.assigns.duration_ms)

    {:noreply,
     socket |> pause() |> seek(Timeline.index_at(socket.assigns.recording, time)) |> at_time(time)}
  end

  def handle_event("jump", %{"to" => "start"}, %{assigns: %{recording: %{}}} = socket),
    do: {:noreply, socket |> pause() |> seek(0)}

  def handle_event("jump", %{"to" => "end"}, %{assigns: %{recording: %{}}} = socket) do
    %{timeline: timeline, duration_ms: duration} = socket.assigns
    {:noreply, socket |> pause() |> seek(Timeline.last_index(timeline)) |> at_time(duration)}
  end

  # Jumps to the next or previous error, or mark, wrapping around.
  def handle_event(to, %{"direction" => direction}, %{assigns: %{recording: %{}}} = socket)
      when to in ~w(error mark) and direction in ~w(next previous) do
    %{recording: recording, index: index} = socket.assigns
    found? = if to == "error", do: &Event.error?/1, else: &Event.mark?/1

    case Events.nearest_index(recording, index, String.to_existing_atom(direction), found?) do
      nil -> {:noreply, socket}
      found -> {:noreply, socket |> pause() |> seek(found)}
    end
  end

  # Opens another page of the visit, from the pages strip or the Visit tab.
  def handle_event("page", %{"id" => id}, %{assigns: %{pages: %{} = pages}} = socket) do
    if Pages.page(pages, id) && id != socket.assigns.id,
      do: {:noreply, socket |> pause() |> switch_page(id)},
      else: {:noreply, socket}
  end

  def handle_event("shortcuts", _params, socket),
    do: {:noreply, update(socket, :shortcuts?, &not/1)}

  def handle_event("close_shortcuts", _params, socket),
    do: {:noreply, assign(socket, :shortcuts?, false)}

  def handle_event("rotate", _params, socket),
    do: {:noreply, update(socket, :rotated?, &not/1)}

  def handle_event("follow_scroll", _params, socket),
    do: {:noreply, update(socket, :follow_scroll?, &not/1)}

  def handle_event("tab", %{"value" => tab}, socket) when tab in ~w(events state visit) do
    {:noreply, assign(socket, :tab, tab)}
  end

  def handle_event("errors_only", _params, socket) do
    {:noreply, socket |> update(:errors_only, &(not &1)) |> filter_events()}
  end

  def handle_event("search_events", %{"q" => query}, socket) do
    {:noreply, socket |> assign(:query, String.trim(query)) |> filter_events()}
  end

  def handle_event("toggle_kind", %{"kind" => name}, socket) do
    case Events.parse_kind(name) do
      {:ok, kind} -> {:noreply, socket |> update(:hidden, &toggle(&1, kind)) |> filter_events()}
      :error -> {:noreply, socket}
    end
  end

  def handle_event("pin_details", _params, %{assigns: %{pinned: nil}} = socket),
    do: {:noreply, assign(socket, :pinned, socket.assigns.index)}

  def handle_event("pin_details", _params, socket), do: {:noreply, assign(socket, :pinned, nil)}

  def handle_event("export_dialog", _params, %{assigns: %{exportable?: true}} = socket) do
    options = Options.new(socket.assigns.context.config.export)

    params = %{
      "from" => "",
      "to" => "",
      "skip_idle" => to_string(options.skip_idle),
      "pointer" => "true",
      "size" => "recorded",
      "fps" => to_string(options.fps),
      "quality" => "balanced"
    }

    {:noreply, assign(socket, :export_dialog, %{params: params, error: nil})}
  end

  def handle_event(
        "export_form",
        %{"export" => params},
        %{assigns: %{export_dialog: %{}}} = socket
      ),
      do: {:noreply, update(socket, :export_dialog, &%{&1 | params: params})}

  # Fills From or To with the moment the player is at.
  def handle_event("export_at", %{"field" => field}, %{assigns: %{export_dialog: %{}}} = socket)
      when field in ~w(from to) do
    seconds = :erlang.float_to_binary(socket.assigns.at / 1_000, decimals: 2)
    {:noreply, update(socket, :export_dialog, &put_in(&1, [:params, field], seconds))}
  end

  def handle_event("close_export_dialog", _params, socket),
    do: {:noreply, assign(socket, :export_dialog, nil)}

  def handle_event("export", %{"export" => params}, %{assigns: %{exportable?: true}} = socket) do
    case Options.parse(params, socket.assigns.context.config.export) do
      {:ok, options} ->
        {:noreply, socket |> assign(:export_dialog, nil) |> start_export(options)}

      {:error, message} ->
        {:noreply, assign(socket, :export_dialog, %{params: params, error: message})}
    end
  end

  # Trying again after a failure uses the options that failed.
  def handle_event("export", _params, %{assigns: %{exportable?: true}} = socket),
    do: {:noreply, start_export(socket, socket.assigns.export && socket.assigns.export.options)}

  def handle_event("cancel_export", _params, %{assigns: %{export: %{id: id}}} = socket) do
    :ok = Export.cancel(id)
    {:noreply, socket}
  end

  def handle_event("cancel_export", _params, socket), do: {:noreply, socket}

  def handle_event("dismiss_export", _params, socket),
    do: {:noreply, assign(socket, :export, nil)}

  def handle_event("delete", _params, socket) do
    %{context: context, recording: recording} = socket.assigns

    with true <- Context.allowed?(socket, :delete, recording),
         :ok <- Catalog.delete(context.config, recording.id) do
      {:noreply, push_navigate(socket, to: Context.path(context, []))}
    else
      false ->
        {:noreply, socket}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Could not delete: #{inspect(reason)}")}
    end
  end

  @impl true
  # Steps to the next event; after the last one, plays on to the end of
  # the pointer track, then stops.
  def handle_info({:advance, ref}, %{assigns: %{playing: %{ref: ref}}} = socket) do
    %{index: index, timeline: timeline} = socket.assigns

    socket =
      if index < Timeline.last_index(timeline),
        do: seek(socket, index + 1),
        else: assign(socket, :at, socket.assigns.next_at)

    # Events can share a time; only the end of the page moves on.
    if socket.assigns.index < Timeline.last_index(timeline) or
         socket.assigns.next_at > socket.assigns.at,
       do: {:noreply, schedule(socket)},
       else: {:noreply, end_of_page(socket)}
  end

  def handle_info({:advance, _stale}, socket), do: {:noreply, socket}

  def handle_info({:next_page, ref, id}, %{assigns: %{playing: %{ref: ref}}} = socket) do
    socket = socket |> assign(playing: nil) |> switch_page(id)
    {:noreply, if(socket.assigns.id == id, do: play(socket), else: socket)}
  end

  def handle_info({:next_page, _stale, _id}, socket), do: {:noreply, socket}

  def handle_info({Channel, {:unrecorded, keys}}, socket),
    do: {:noreply, assign(socket, :unrecorded, keys)}

  def handle_info({Channel, :frame_ready}, %{assigns: %{recording: nil}} = socket) do
    {:noreply, assign(socket, :frame_ready?, true)}
  end

  def handle_info({Channel, :frame_ready}, socket) do
    socket = socket |> assign(:frame_ready?, true) |> hand_over()
    :ok = Channel.seek(socket.assigns.channel, socket.assigns.index)
    {:noreply, socket}
  end

  def handle_info({:redaction_progress, done, total}, %{assigns: %{recording: nil}} = socket) do
    {:noreply, assign(socket, :progress, {done, total})}
  end

  def handle_info({:redaction_progress, _done, _total}, socket), do: {:noreply, socket}

  def handle_info({Export, %{recording_id: id} = job}, %{assigns: %{id: id}} = socket),
    do: {:noreply, assign(socket, :export, job)}

  def handle_info({Export, _other_recording}, socket), do: {:noreply, socket}

  defp seek(socket, index) do
    timeline = Timeline.seek(socket.assigns.timeline, max(index, socket.assigns.first_render))
    :ok = Channel.seek(socket.assigns.channel, timeline.index)

    assign(socket,
      # Turned to look at it, the device turns back when the recording turns.
      rotated?:
        socket.assigns.rotated? and not turned?(socket.assigns[:viewport], timeline.viewport),
      timeline: timeline,
      index: timeline.index,
      at: if(timeline.event, do: timeline.event.at, else: 0),
      next_at: next_at(timeline, socket.assigns.duration_ms),
      viewport: timeline.viewport,
      url: timeline.url,
      replayed: shown_assigns(timeline.assigns),
      before: timeline.before,
      changed: Event.changed_keys(timeline.event)
    )
  end

  # The app's migrations replay applies to this recording, by name.
  defp migrations_applied(recording) do
    stamp = recording.code && recording.code[:migration]

    for {_version, migration} <- Migration.pending(Migration.all(recording.view), stamp),
        do: migration |> Module.split() |> List.last()
  end

  defp turned?(%{} = before, %{} = now), do: Client.orientation(before) != Client.orientation(now)
  defp turned?(_before, _now), do: false

  # The next event's offset, or the end of the recording after the last.
  defp next_at(timeline, duration_ms) do
    case Timeline.next(timeline) do
      nil -> duration_ms
      event -> event.at
    end
  end

  defp play(socket) do
    %{index: index} = socket.assigns

    if index >= Timeline.last_index(socket.assigns.timeline) and
         socket.assigns.at >= socket.assigns.duration_ms,
       do: socket |> seek(0) |> schedule(),
       else: schedule(socket)
  end

  defp schedule(socket) do
    %{at: at, next_at: next_at, speed: speed} = socket.assigns
    ref = make_ref()
    timer = Process.send_after(self(), {:advance, ref}, div(next_at - at, speed))
    assign(socket, :playing, %{timer: timer, ref: ref, since: now()})
  end

  # The scrubber and the pointer moved on between events while playing, so
  # pausing keeps the time playback reached rather than the last event's.
  defp pause(%{assigns: %{playing: %{timer: timer, since: since}}} = socket) do
    Process.cancel_timer(timer)
    %{at: at, next_at: next_at, speed: speed} = socket.assigns
    reached = min(at + (now() - since) * speed, next_at)
    assign(socket, at: reached, playing: nil, gap: nil)
  end

  defp pause(socket), do: socket

  defp redaction_label(nil), do: "Redacting the recording before showing it…"
  defp redaction_label({_done, 0}), do: "Redacting the recording before showing it…"

  defp redaction_label({done, total}),
    do: "Redacting the recording before showing it… #{done} / #{total} events"

  defp redaction_percent({done, total}) when total > 0, do: Float.round(done / total * 100, 1)
  defp redaction_percent(_progress), do: 0.0

  # The channel is made at each mount, and the page's first render is not
  # connected, so the frame gets its address only once the player is: an
  # address in that first render would load the frame, then load it again
  # with the connected player's channel.
  defp frame_src(%{connected?: false}), do: nil

  defp frame_src(%{context: context, id: id, channel: channel}),
    do: Context.path(context, [id, "frame"]) <> "?channel=#{channel}"

  defp toggle(set, member) do
    if MapSet.member?(set, member), do: MapSet.delete(set, member), else: MapSet.put(set, member)
  end

  # The event list's groups change with its filters, not with the position.
  defp filter_events(%{assigns: %{interactions: interactions} = assigns} = socket) do
    filters = Map.take(assigns, [:hidden, :query, :errors_only])
    assign(socket, :event_groups, Events.visible(interactions, filters))
  end

  # The client state assign is listed once the browser reported some.
  defp shown_assigns(%{phoenix_replay_state: state} = assigns) when state == %{},
    do: Map.delete(assigns, :phoenix_replay_state)

  defp shown_assigns(assigns), do: assigns

  defp now, do: System.monotonic_time(:millisecond)

  defp at_time(socket, nil), do: socket

  defp at_time(%{assigns: %{at: at, next_at: next_at}} = socket, requested),
    do: assign(socket, :at, requested |> Params.integer(at) |> max(at) |> min(next_at))

  # The recording list filtered by `criteria`, such as where a visit came from.
  defp filtered_list(context, criteria) do
    Context.path(context, []) <>
      "?" <> URI.encode_query(Filter.to_params(struct!(Filter, criteria)))
  end
end
