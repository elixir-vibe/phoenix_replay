defmodule PhoenixReplay.Web.Live.Show do
  @moduledoc """
  Plays back a recording.

  Playback is driven by the server: each step schedules the next one after
  the recorded gap divided by the speed, and tells the frame which event to
  show through `PhoenixReplay.Web.Player.Channel`. The `Scrubber` hook only maps
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
  is available. The export runs under `PhoenixReplay.Export.Server`, and
  the player follows its progress and links the video when it is ready.
  """

  use Phoenix.LiveView

  import PhoenixIconify, only: [icon: 1]
  import PhoenixReplay.Web.Components.{Core, Player}

  alias PhoenixReplay.Recording.{Filter, PointerTrack, Timeline}
  alias PhoenixReplay.{Catalog, Export}
  alias PhoenixReplay.Web.{Context, Download, Layouts, Params}
  alias PhoenixReplay.Web.Player.{Channel, Events}

  @speeds [1, 2, 5, 10]
  # The most sessions of one browser tab the player links between.
  @journey_limit 200
  @progress_every 25

  @impl true
  def mount(%{"id" => id} = params, _session, socket) do
    context = Context.fetch(socket)
    channel = Channel.new()
    if connected?(socket), do: Channel.subscribe(channel)

    socket =
      assign(socket,
        page_title: "Replay",
        assets: Layouts.dashboard_assets(context),
        context: context,
        id: id,
        recording: nil,
        live?: Catalog.live?(id),
        frame_ready?: false,
        progress: nil,
        load_error?: false,
        channel: channel,
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
        export: nil,
        exportable?: false,
        # A link to a moment opens the player there.
        start_at: Params.integer(params["at"], nil)
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
      interactions: Events.interactions(recording.events),
      kinds: Events.kinds(recording),
      kind_counts: Events.kind_counts(recording),
      first_error: Events.first_error_index(recording),
      dropped: Events.dropped_count(recording),
      journey: journey(socket, recording)
    )
    |> hand_over()
    |> filter_events()
    |> seek(socket.assigns.start_at || Timeline.first_render_index(recording))
  end

  # A live session's frame waits for the redacted recording from the player.
  defp hand_over(%{assigns: %{live?: true, frame_ready?: true}} = socket) do
    :ok = Channel.load(socket.assigns.channel, socket.assigns.recording)
    socket
  end

  defp hand_over(socket), do: socket

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

  def handle_event("rotate", _params, socket),
    do: {:noreply, update(socket, :rotated?, &not/1)}

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

  def handle_event("export", _params, %{assigns: %{exportable?: true}} = socket) do
    case Export.start(socket.assigns.id, socket.assigns.context.config) do
      {:ok, job} -> {:noreply, assign(socket, :export, job)}
      {:error, reason} -> {:noreply, put_flash(socket, :error, Export.describe(reason))}
    end
  end

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

    # Events can share a time; only the end of the recording stops playing.
    if socket.assigns.index < Timeline.last_index(timeline) or
         socket.assigns.next_at > socket.assigns.at,
       do: {:noreply, schedule(socket)},
       else: {:noreply, assign(socket, :playing, nil)}
  end

  def handle_info({:advance, _stale}, socket), do: {:noreply, socket}

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
    timeline = Timeline.seek(socket.assigns.timeline, index)
    :ok = Channel.seek(socket.assigns.channel, timeline.index)

    assign(socket,
      timeline: timeline,
      index: timeline.index,
      at: if(timeline.event, do: timeline.event.at, else: 0),
      next_at: next_at(timeline, socket.assigns.duration_ms),
      viewport: timeline.viewport,
      url: timeline.url,
      replayed: shown_assigns(timeline.assigns),
      before: timeline.before,
      changed: Events.changed_keys(timeline.event)
    )
  end

  # The next event's offset, or the end of the recording after the last.
  defp next_at(timeline, duration_ms) do
    case Timeline.next(timeline) do
      nil -> duration_ms
      event -> event.at
    end
  end

  defp play(socket) do
    %{recording: recording, index: index} = socket.assigns

    if index >= Timeline.last_index(socket.assigns.timeline) and
         socket.assigns.at >= socket.assigns.duration_ms,
       do: socket |> seek(Timeline.first_render_index(recording)) |> schedule(),
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
    assign(socket, at: reached, playing: nil)
  end

  defp pause(socket), do: socket

  defp redaction_label(nil), do: "Redacting the session before showing it…"
  defp redaction_label({_done, 0}), do: "Redacting the session before showing it…"

  defp redaction_label({done, total}),
    do: "Redacting the session before showing it… #{done} / #{total} events"

  defp redaction_percent({done, total}) when total > 0, do: Float.round(done / total * 100, 1)
  defp redaction_percent(_progress), do: 0.0

  # The sessions of the recording's browser tab, oldest first, when it has more than one.
  defp journey(socket, %{id: id, client: %{tab: tab}}) when is_binary(tab) do
    %{config: config} = socket.assigns.context
    filter = %Filter{tab: tab}
    now = System.system_time(:millisecond)
    allowed? = &Context.allowed?(socket, :list, &1)
    {stored, _total} = Catalog.query(config, filter, now: now, limit: @journey_limit)

    sessions =
      (Catalog.live(filter, now) ++ stored)
      |> Enum.uniq_by(& &1.id)
      |> Enum.filter(allowed?)
      |> Enum.sort_by(& &1.connected_at)

    case {Enum.find_index(sessions, &(&1.id == id)), sessions} do
      {index, [_first, _second | _rest]} when is_integer(index) ->
        context = socket.assigns.context

        %{
          tab_path: Context.path(context, []) <> "?" <> URI.encode_query(%{"tab" => tab}),
          position: index + 1,
          total: length(sessions),
          previous: index > 0 && Context.path(context, [Enum.at(sessions, index - 1).id]),
          next: (next = Enum.at(sessions, index + 1)) && Context.path(context, [next.id])
        }

      _alone ->
        nil
    end
  end

  defp journey(_socket, _recording), do: nil

  @impl true
  def render(%{recording: nil} = assigns) do
    ~H"""
    <.app_bar>
      <:mark><.icon name="lucide:circle-play" class="size-5 text-accent" /></:mark>
      <:crumb>
        <.link navigate={Context.path(@context, [])} class="hover:text-accent">PhoenixReplay</.link>
      </:crumb>
      <:crumb>Live session</:crumb>
    </.app_bar>
    <main class="flex flex-col gap-4 p-4 sm:p-5">
      <.flash flash={@flash} />
      <p :if={@load_error?} role="alert" class="text-sm text-error">
        Could not redact this session, so it is not shown.
      </p>
      <div :if={!@load_error?} id="replay-redaction" role="status" class="max-w-md text-sm text-muted">
        <p class="mb-2">{redaction_label(@progress)}</p>
        <.progress label="Redaction" value={redaction_percent(@progress)} />
      </div>
      <.replay_frame :if={!@load_error?} src={frame_src(assigns)} ready={@frame_ready?} />
    </main>
    """
  end

  def render(assigns) do
    ~H"""
    <.player_header
      recording={@recording}
      back={Context.path(@context, [])}
      duration_ms={@duration_ms}
      error_count={@error_count}
      first_error={@first_error}
      dropped={@dropped}
      at={@at}
      link={Context.path(@context, [@recording.id]) <> "?at=#{@index}"}
      can_export={@exportable?}
    />
    <.export_status
      :if={@export}
      job={@export}
      download={
        @export.status == :done &&
          Context.path(@context, [@recording.id, "video", Download.sign(@socket, @export)])
      }
    />
    <div class="flex flex-wrap items-stretch">
      <main class="flex min-w-0 flex-[999_1_40rem] flex-col gap-4 p-4 sm:p-5">
        <.flash flash={@flash} />
        <.replay_frame
          src={frame_src(assigns)}
          url={@url}
          viewport={@viewport}
          mode={@frame_mode}
          rotated={@rotated?}
          below="replay-playback"
          pointer={@pointer}
          ready={@frame_ready?}
        />
        <.playback
          id="replay-playback"
          recording={@recording}
          index={@index}
          at={@at}
          next_at={@next_at}
          duration_ms={@duration_ms}
          playing={@playing != nil}
          speed={@speed}
          speeds={@speeds}
        />
      </main>
      <aside
        aria-label="Session"
        class="flex max-w-full min-w-0 flex-[1_1_24rem] flex-col border-l border-line bg-surface"
      >
        <.tabs
          id="replay-tabs"
          label="Session details"
          tabs={[{"events", "Events"}, {"state", "State"}, {"visit", "Visit"}]}
          value={@tab}
          event="tab"
        />
        <div id="replay-tabs-panel" role="tabpanel" class="flex min-h-0 flex-1 flex-col">
          <.event_list
            :if={@tab == "events"}
            groups={@event_groups}
            kinds={@kinds}
            counts={@kind_counts}
            error_count={@error_count}
            index={@index}
            hidden={@hidden}
            query={@query}
            errors_only={@errors_only}
          />
          <.state
            :if={@tab == "state"}
            assigns={@replayed}
            before={@before}
            changed={@changed}
            at={@at}
          />
          <.visit
            :if={@tab == "visit"}
            recording={@recording}
            viewport={@viewport}
            journey={@journey}
          />
        </div>
      </aside>
    </div>
    """
  end

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
end
