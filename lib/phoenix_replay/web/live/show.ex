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

  alias PhoenixReplay.Recording.{Event, Timeline}
  alias PhoenixReplay.Recordings
  alias PhoenixReplay.Web.{Context, Format, Layouts, Params, Playback}
  alias PhoenixReplay.Web.Player.Events

  @speeds [1, 2, 5, 10]
  @progress_every 25

  @impl true
  def mount(%{"id" => id}, _session, socket) do
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
        frame_mode: "fit"
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
    socket
    |> assign(
      page_title: "Replay · #{inspect(recording.view)}",
      recording: recording,
      progress: nil,
      duration_ms: Timeline.duration_ms(recording),
      kinds: Events.kinds(recording),
      error_count: Events.error_count(recording),
      dropped: Events.dropped_count(recording),
      journey: journey(socket, recording)
    )
    |> hand_over()
    |> seek(Timeline.first_render_index(recording))
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

  def handle_event("speed", %{"speed" => speed}, socket) do
    speed = Params.integer(speed, 1)
    speed = if speed in @speeds, do: speed, else: 1
    socket = assign(socket, :speed, speed)
    {:noreply, if(socket.assigns.playing, do: socket |> pause() |> play(), else: socket)}
  end

  def handle_event("frame_mode", %{"value" => mode}, socket) when mode in ~w(fit actual) do
    {:noreply, assign(socket, :frame_mode, mode)}
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

    assign(socket,
      index: index,
      event: Timeline.event_at(recording, index),
      at: event_at(recording, index),
      next_at: event_at(recording, min(index + 1, Timeline.last_index(recording))),
      viewport: Timeline.viewport_at(recording, index),
      assigns_preview: recording |> Timeline.assigns_at(index) |> inspect(pretty: true, limit: 50)
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
    sessions =
      socket.assigns.context.config
      |> Recordings.list()
      |> Enum.filter(&(&1.tab == tab and Context.allowed?(socket, :list, &1)))
      |> Enum.sort_by(& &1.connected_at)

    case {Enum.find_index(sessions, &(&1.id == id)), sessions} do
      {index, [_first, _second | _rest]} when is_integer(index) ->
        %{
          tab: tab,
          position: index + 1,
          total: length(sessions),
          previous: if(index > 0, do: Enum.at(sessions, index - 1)),
          next: Enum.at(sessions, index + 1)
        }

      _alone ->
        nil
    end
  end

  defp journey(_socket, _recording), do: nil

  attr :client, :map, required: true

  # How the visit started and the request headers kept for it.
  defp visit(%{client: client} = assigns) do
    assigns =
      assign(assigns,
        landing: client[:landing],
        headers: client[:headers] || %{}
      )

    ~H"""
    <div
      :if={@landing || @headers != %{}}
      id="replay-visit"
      class="mt-2 flex flex-wrap items-center gap-x-3 gap-y-1 text-sm text-muted"
    >
      <.badge :if={@landing && Format.campaign(@landing.params)}>
        {Format.campaign(@landing.params)}
      </.badge>
      <span :if={@landing && Format.referrer_host(@landing.referrer)} title={@landing.referrer}>
        from {Format.referrer_host(@landing.referrer)}
      </span>
      <span :if={@landing}>
        landed on <code class="font-mono text-ink">{@landing.path}</code>
        at {Format.timestamp(@landing.at)}
      </span>
      <details class="basis-full">
        <summary class="cursor-pointer select-none hover:text-ink">Visit details</summary>
        <.data_list class="mt-2">
          <:item
            :for={{name, value} <- Enum.sort(if(@landing, do: @landing.params, else: %{}))}
            title={name}
          >
            {value}
          </:item>
          <:item :if={@landing && @landing.referrer} title="referrer">{@landing.referrer}</:item>
          <:item :for={{name, value} <- Enum.sort(@headers)} title={name}>{value}</:item>
        </.data_list>
      </details>
    </div>
    """
  end

  attr :context, Context, required: true
  attr :id, :string, required: true
  attr :channel, :string, required: true
  attr :viewport, :map, default: nil
  attr :mode, :string, default: "fit"

  # The frame renders at the recorded viewport, keeping its aspect ratio:
  # fitted to the window, or at 100% in a scrolling box. The FrameViewport
  # hook writes the sizes into the ignored style element and the scale into
  # the ignored label, so the frame itself stays server-rendered.
  defp frame(assigns) do
    ~H"""
    <section
      id="replay-viewport"
      phx-hook="FrameViewport"
      data-width={@viewport && @viewport.width}
      data-height={@viewport && @viewport.height}
      data-mode={@mode}
      class="mb-4 overflow-hidden rounded-lg border border-line bg-surface"
    >
      <style id="replay-viewport-style" phx-update="ignore">
      </style>
      <div
        :if={@viewport}
        class="flex items-center gap-2 border-b border-line bg-chrome px-3 py-1.5 text-xs text-muted"
      >
        <span
          id="replay-viewport-scale"
          phx-update="ignore"
          data-scale-label
          class="font-mono tabular-nums"
        ></span>
        <span class="flex-1"></span>
        <.segmented
          label="Frame size"
          options={[{"fit", "Fit"}, {"actual", "100%"}]}
          value={@mode}
          event="frame_mode"
        />
      </div>
      <div id="replay-viewport-box" class="bg-canvas">
        <iframe
          id="replay-frame"
          title="Replay"
          src={Context.path(@context, [@id, "frame"]) <> "?channel=#{@channel}"}
          class="block h-[600px] w-full border-0"
        ></iframe>
      </div>
    </section>
    """
  end

  attr :context, Context, required: true

  defp back(assigns) do
    ~H"""
    <.link
      navigate={Context.path(@context, [])}
      class="inline-flex items-center gap-1 text-sm text-muted hover:text-ink"
    >
      <.icon name="lucide:arrow-left" class="size-4" /> Recordings
    </.link>
    """
  end

  defp position(_at, 0), do: 0
  defp position(at, duration_ms), do: Float.round(at / duration_ms * 100, 3)

  @impl true
  def render(%{recording: nil} = assigns) do
    ~H"""
    <main class="mx-auto max-w-6xl px-4 py-6">
      <.flash flash={@flash} />
      <header class="mb-4">
        <.back context={@context} />
        <h1 class="mt-1 text-xl font-semibold">Live session</h1>
        <p :if={@load_error?} role="alert" class="text-sm text-error">
          Could not redact this session, so it is not shown.
        </p>
        <div
          :if={!@load_error?}
          id="replay-redaction"
          role="status"
          class="mt-2 max-w-md text-sm text-muted"
        >
          <p class="mb-2">{redaction_label(@progress)}</p>
          <.progress label="Redaction" value={redaction_percent(@progress)} />
        </div>
      </header>
      <.frame :if={!@load_error?} context={@context} id={@id} channel={@channel} />
    </main>
    """
  end

  def render(assigns) do
    ~H"""
    <main class="mx-auto max-w-6xl px-4 py-6">
      <.flash flash={@flash} />
      <header class="mb-4">
        <div class="flex items-center justify-between gap-3">
          <.back context={@context} />
          <.button variant="danger" phx-click="delete" data-confirm="Delete this recording?">
            <.icon name="lucide:trash-2" class="size-3.5" /> Delete recording
          </.button>
        </div>
        <h1 class="mt-1 text-xl font-semibold">{inspect(@recording.view)}</h1>
        <p class="flex flex-wrap items-center gap-x-1 text-sm text-muted tabular-nums">
          Session <code class="font-mono text-ink">{String.slice(@recording.id, 0, 12)}</code>
          · {Format.count(length(@recording.events), "event")} · {Format.clock(@duration_ms)}
          <.badge :if={@error_count > 0} tone="error">
            {Format.count(@error_count, "error")}
          </.badge>
          <span :if={@dropped > 0} title={inspect(@recording.dropped)}>
            · {@dropped} collected events over the limit dropped
          </span>
        </p>
        <p
          :if={@viewport || @recording.client.user_agent || @recording.client.referer || @journey}
          class="mt-1 flex flex-wrap items-center gap-x-3 gap-y-1 text-sm text-muted"
        >
          <span :if={@viewport} id="replay-device" title={@recording.client.user_agent}>
            {Format.viewport(@viewport)}<span :if={
              label = Format.device(@recording.client.user_agent)
            }> · {label}</span>
          </span>
          <span :if={!@viewport && @recording.client.user_agent} title={@recording.client.user_agent}>
            {Format.device(@recording.client.user_agent) || "Unknown browser"}
          </span>
          <span :if={@recording.client.referer} title={@recording.client.referer}>
            Came from
            <code class="font-mono text-ink">{Format.path_of(@recording.client.referer)}</code>
          </span>
          <span :if={@journey} id="replay-journey" class="inline-flex items-center gap-2">
            <.link
              navigate={Context.path(@context, []) <> "?" <> URI.encode_query(%{"tab" => @journey.tab})}
              class="underline decoration-line hover:text-ink"
            >
              Session {@journey.position} of {@journey.total} in this tab
            </.link>
            <.link
              :if={@journey.previous}
              navigate={Context.path(@context, [@journey.previous.id])}
              class="inline-flex items-center gap-1 hover:text-ink"
            >
              <.icon name="lucide:arrow-left" class="size-3.5" /> Previous
            </.link>
            <.link
              :if={@journey.next}
              navigate={Context.path(@context, [@journey.next.id])}
              class="inline-flex items-center gap-1 hover:text-ink"
            >
              Next <.icon name="lucide:arrow-right" class="size-3.5" />
            </.link>
          </span>
        </p>
        <.visit client={@recording.client} />
      </header>

      <.panel padded class="mb-4">
        <div class="mb-3 flex items-center gap-1.5">
          <.icon_button phx-click="previous" label="Previous event" disabled={@index == 0}>
            <.icon name="lucide:skip-back" class="size-4" />
          </.icon_button>
          <.icon_button phx-click="toggle" label={if @playing, do: "Pause", else: "Play"}>
            <.icon :if={@playing} name="lucide:pause" class="size-4" />
            <.icon :if={!@playing} name="lucide:play" class="size-4" />
          </.icon_button>
          <.icon_button
            phx-click="next"
            label="Next event"
            disabled={@index == length(@recording.events) - 1}
          >
            <.icon name="lucide:skip-forward" class="size-4" />
          </.icon_button>
          <span class="ml-2 font-mono text-xs text-muted tabular-nums">
            {Format.clock(@at)} / {Format.clock(@duration_ms)}
          </span>
          <span class="flex-1"></span>
          <form id="replay-speed-form" phx-change="speed">
            <label class="sr-only" for="replay-speed">Playback speed</label>
            <select
              id="replay-speed"
              name="speed"
              class="h-8 rounded-md border border-line bg-surface px-2 font-mono text-xs"
            >
              <option :for={speed <- @speeds} value={speed} selected={speed == @speed}>
                {speed}×
              </option>
            </select>
          </form>
        </div>

        <div
          id="replay-scrubber"
          phx-hook="Scrubber"
          role="slider"
          aria-label="Playback position"
          aria-valuemin="0"
          aria-valuemax={length(@recording.events) - 1}
          aria-valuenow={@index}
          tabindex="0"
          data-offsets={JSON.encode!(Enum.map(@recording.events, & &1.at))}
          data-at={@at}
          data-next-at={@next_at}
          data-duration={@duration_ms}
          data-speed={@speed}
          data-playing={to_string(@playing != nil)}
          class="relative flex h-5 cursor-pointer touch-none items-center select-none"
        >
          <div class="relative h-1 flex-1 rounded-full bg-track">
            <span
              :for={event <- @recording.events}
              class={[
                "absolute top-1/2 -translate-x-1/2 -translate-y-1/2 rounded-full",
                Events.marker_class(event)
              ]}
              style={"left: #{position(event.at, @duration_ms)}%"}
              title={Events.label(event)}
            ></span>
          </div>
          <span
            data-thumb
            class="absolute top-1/2 size-3.5 -translate-x-1/2 -translate-y-1/2 rounded-full border-2 border-surface bg-ink shadow-sm"
            style={"left: #{position(@at, @duration_ms)}%"}
          ></span>
        </div>
      </.panel>

      <.frame
        context={@context}
        id={@recording.id}
        channel={@channel}
        viewport={@viewport}
        mode={@frame_mode}
      />

      <div class="grid grid-cols-1 gap-4 lg:grid-cols-2">
        <.panel title="Events">
          <:actions>
            <.chip
              :for={kind <- @kinds}
              :if={length(@kinds) > 1}
              pressed={not MapSet.member?(@hidden, kind)}
              phx-click="toggle_kind"
              phx-value-kind={kind}
            >
              {Events.kind_label(kind)}
            </.chip>
            <span class="text-xs text-faint tabular-nums">{length(@recording.events)}</span>
          </:actions>
          <ol
            id="replay-events"
            phx-hook="EventList"
            class="relative max-h-[clamp(300px,40vh,600px)] overflow-y-auto overscroll-contain p-1.5"
          >
            <li
              :for={{event, index} <- Enum.with_index(@recording.events)}
              :if={not MapSet.member?(@hidden, Events.kind(event.type))}
            >
              <button
                type="button"
                phx-click="seek"
                phx-value-index={index}
                aria-current={index == @index && "step"}
                class={[
                  "flex w-full min-w-0 items-center gap-2 rounded-md px-2.5 py-1.5 text-left text-[13px]",
                  Events.collected?(event) && "pl-7 text-xs",
                  index == @index && "bg-ink text-on-ink",
                  index != @index && "hover:bg-hover",
                  index > @index && "text-faint",
                  index < @index && Event.error?(event) && "text-error"
                ]}
              >
                <.event_icon type={event.type} class="size-3.5 shrink-0 opacity-70" />
                <span class="min-w-0 flex-1 truncate">{Events.label(event)}</span>
                <span
                  :if={duration = Event.duration(event)}
                  class="shrink-0 font-mono text-[11px] tabular-nums opacity-60"
                >
                  {Format.milliseconds(duration)}
                </span>
                <span class="shrink-0 font-mono text-[11px] tabular-nums opacity-60">
                  {Format.clock(event.at)}
                </span>
              </button>
            </li>
          </ol>
        </.panel>

        <div class="flex min-w-0 flex-col gap-4">
          <.panel :if={@event && @event.type in [:telemetry, :log, :exit]} title="Details">
            <pre class="max-h-60 overflow-auto p-4 font-mono text-xs leading-relaxed break-words whitespace-pre-wrap text-ink">{inspect(@event.data, pretty: true, limit: 50)}</pre>
          </.panel>
          <.panel title="Assigns">
            <pre class="max-h-[clamp(300px,40vh,600px)] overflow-auto p-4 font-mono text-xs leading-relaxed break-words whitespace-pre-wrap text-ink">{@assigns_preview}</pre>
          </.panel>
        </div>
      </div>
    </main>
    """
  end
end
