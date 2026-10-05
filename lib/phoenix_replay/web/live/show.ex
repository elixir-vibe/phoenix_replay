defmodule PhoenixReplay.Web.Live.Show do
  @moduledoc """
  Plays back a recording.

  Playback is driven by the server: each step schedules the next one after
  the recorded gap divided by the speed, and tells the frame which event to
  show through `PhoenixReplay.Web.Playback`. The `Scrubber` hook only maps
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
  """

  use Phoenix.LiveView

  import PhoenixIconify, only: [icon: 1]
  import PhoenixReplay.Web.Components.{Core, Player}

  alias PhoenixReplay.Recording.{Pointer, Timeline}
  alias PhoenixReplay.Recordings
  alias PhoenixReplay.Recordings.Filter
  alias PhoenixReplay.Web.{Context, Layouts, Params, Playback}
  alias PhoenixReplay.Web.Player.Events

  @speeds [1, 2, 5, 10]
  # The most sessions of one browser tab the player links between.
  @journey_limit 200
  @progress_every 25

  @impl true
  def mount(%{"id" => id} = params, _session, socket) do
    context = Context.fetch(socket)
    channel = Playback.new_channel()
    if connected?(socket), do: Playback.subscribe(channel)

    socket =
      assign(socket,
        page_title: "Replay",
        assets: Layouts.dashboard_assets(context),
        context: context,
        id: id,
        recording: nil,
        live?: Recordings.live?(id),
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
        # A link to a moment opens the player there.
        start_at: Params.integer(params["at"], nil)
      )

    cond do
      not socket.assigns.live? -> {:ok, loaded(socket, Context.fetch_recording!(socket, id))}
      connected?(socket) -> {:ok, load_live(socket)}
      true -> {:ok, socket}
    end
  end

  defp load_live(socket) do
    %{context: context, id: id} = socket.assigns
    player = self()

    socket
    |> assign(:progress, {0, 0})
    |> start_async(:recording, fn ->
      Recordings.fetch(context.config, id, progress: &report_progress(player, &1, &2))
    end)
  end

  defp report_progress(player, done, total) when done == total or rem(done, @progress_every) == 0,
    do: send(player, {:redaction_progress, done, total})

  defp report_progress(_player, _done, _total), do: :ok

  defp loaded(socket, recording) do
    # Stepping and seeking follow LiveView events; the overlay plays the
    # pointer track against the same clock.
    {recording, pointer} = Pointer.split(recording)

    socket
    |> assign(
      page_title: "Replay · #{inspect(recording.view)}",
      recording: recording,
      pointer: pointer,
      progress: nil,
      duration_ms: Timeline.duration_ms(recording),
      error_count: Events.error_count(recording),
      first_error: Events.first_error_index(recording),
      dropped: Events.dropped_count(recording),
      journey: journey(socket, recording)
    )
    |> hand_over()
    |> seek(socket.assigns.start_at || Timeline.first_render_index(recording))
  end

  # A live session's frame waits for the redacted recording from the player.
  defp hand_over(%{assigns: %{live?: true, frame_ready?: true}} = socket) do
    :ok = Playback.load(socket.assigns.channel, socket.assigns.recording)
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
  def handle_event("seek", %{"index" => index}, socket) do
    {:noreply, socket |> pause() |> seek(Params.integer(index, socket.assigns.index))}
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

  def handle_event("tab", %{"value" => tab}, socket) when tab in ~w(events state visit) do
    {:noreply, assign(socket, :tab, tab)}
  end

  def handle_event("errors_only", _params, socket) do
    {:noreply, update(socket, :errors_only, &(not &1))}
  end

  def handle_event("search_events", %{"q" => query}, socket) do
    {:noreply, assign(socket, :query, String.trim(query))}
  end

  def handle_event("toggle_kind", %{"kind" => kind}, socket) do
    hidden = socket.assigns.hidden

    hidden =
      if MapSet.member?(hidden, kind),
        do: MapSet.delete(hidden, kind),
        else: MapSet.put(hidden, kind)

    {:noreply, assign(socket, :hidden, hidden)}
  end

  def handle_event("delete", _params, socket) do
    %{context: context, recording: recording} = socket.assigns

    with true <- Context.allowed?(socket, :delete, recording),
         :ok <- Recordings.delete(context.config, recording.id) do
      {:noreply, push_navigate(socket, to: Context.path(context, []))}
    else
      false ->
        {:noreply, socket}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Could not delete: #{inspect(reason)}")}
    end
  end

  @impl true
  def handle_info({:advance, ref}, %{assigns: %{playing: {_timer, ref}}} = socket) do
    socket = seek(socket, socket.assigns.index + 1)

    if socket.assigns.index < Timeline.last_index(socket.assigns.recording),
      do: {:noreply, schedule(socket)},
      else: {:noreply, assign(socket, :playing, nil)}
  end

  def handle_info({:advance, _stale}, socket), do: {:noreply, socket}

  def handle_info({Playback, :frame_ready}, %{assigns: %{recording: nil}} = socket) do
    {:noreply, assign(socket, :frame_ready?, true)}
  end

  def handle_info({Playback, :frame_ready}, socket) do
    socket = socket |> assign(:frame_ready?, true) |> hand_over()
    :ok = Playback.seek(socket.assigns.channel, socket.assigns.index)
    {:noreply, socket}
  end

  def handle_info({:redaction_progress, done, total}, %{assigns: %{recording: nil}} = socket) do
    {:noreply, assign(socket, :progress, {done, total})}
  end

  def handle_info({:redaction_progress, _done, _total}, socket), do: {:noreply, socket}

  defp seek(socket, index) do
    %{recording: recording, channel: channel} = socket.assigns
    index = Timeline.clamp(recording, index)
    :ok = Playback.seek(channel, index)

    event = Timeline.event_at(recording, index)

    assign(socket,
      index: index,
      at: event_at(recording, index),
      next_at: event_at(recording, min(index + 1, Timeline.last_index(recording))),
      viewport: Timeline.viewport_at(recording, index),
      url: Timeline.url_at(recording, index),
      replayed: Timeline.assigns_at(recording, index),
      changed: Events.changed_keys(event)
    )
  end

  defp play(socket) do
    %{recording: recording, index: index} = socket.assigns

    if index >= Timeline.last_index(recording),
      do: socket |> seek(Timeline.first_render_index(recording)) |> schedule(),
      else: schedule(socket)
  end

  defp schedule(socket) do
    %{at: at, next_at: next_at, speed: speed} = socket.assigns
    ref = make_ref()
    timer = Process.send_after(self(), {:advance, ref}, div(next_at - at, speed))
    assign(socket, :playing, {timer, ref})
  end

  defp pause(%{assigns: %{playing: {timer, _ref}}} = socket) do
    Process.cancel_timer(timer)
    assign(socket, :playing, nil)
  end

  defp pause(socket), do: socket

  defp event_at(recording, index) do
    case Timeline.event_at(recording, index) do
      nil -> 0
      event -> event.at
    end
  end

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
    {stored, _total} = Recordings.query(config, filter, now: now, limit: @journey_limit)

    sessions =
      (Recordings.live(filter, now) ++ stored)
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
      <.replay_frame :if={!@load_error?} src={frame_src(assigns)} />
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
    />
    <div class="flex flex-wrap items-stretch">
      <main class="flex min-w-0 flex-[999_1_40rem] flex-col gap-4 p-4 sm:p-5">
        <.flash flash={@flash} />
        <.replay_frame
          src={frame_src(assigns)}
          url={@url}
          viewport={@viewport}
          mode={@frame_mode}
          below="replay-playback"
          pointer={@pointer}
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
            recording={@recording}
            index={@index}
            hidden={@hidden}
            query={@query}
            errors_only={@errors_only}
          />
          <.state :if={@tab == "state"} assigns={@replayed} changed={@changed} at={@at} />
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
end
