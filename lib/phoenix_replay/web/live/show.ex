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

  import PhoenixReplay.Web.Components

  alias PhoenixReplay.Recording.{Event, Timeline}
  alias PhoenixReplay.Recordings
  alias PhoenixReplay.Web.{Context, Layouts, Playback}

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
        hidden: MapSet.new()
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
      kinds: kinds(recording),
      error_count: Enum.count(recording.events, &Event.error?/1),
      dropped: Enum.sum_by(recording.dropped, fn {_name, count} -> count end),
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
    {:noreply, socket |> pause() |> seek(parse_integer(index, socket.assigns.index))}
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
    speed = parse_integer(speed, 1)
    speed = if speed in @speeds, do: speed, else: 1
    socket = assign(socket, :speed, speed)
    {:noreply, if(socket.assigns.playing, do: socket |> pause() |> play(), else: socket)}
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

  # Kinds present in the recording, shown as filters when there is more than one.
  defp kinds(recording) do
    recording.events
    |> Enum.map(&event_kind(&1.type))
    |> Enum.uniq()
    |> Enum.sort_by(&(&1 != "liveview"))
  end

  defp collected?(%Event{type: type}), do: type in [:telemetry, :log]

  defp kind_label("liveview"), do: "LiveView"
  defp kind_label("telemetry"), do: "Telemetry"
  defp kind_label("logs"), do: "Logs"

  defp redaction_label(nil), do: "Redacting the session before showing it…"
  defp redaction_label({_done, 0}), do: "Redacting the session before showing it…"

  defp redaction_label({done, total}),
    do: "Redacting the session before showing it… #{done} / #{total} events"

  defp redaction_percent({done, total}) when total > 0, do: Float.round(done / total * 100, 1)
  defp redaction_percent(_progress), do: 0

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
      class="mt-2 flex flex-wrap items-center gap-x-3 gap-y-1 text-sm text-neutral-500"
    >
      <span
        :if={@landing && campaign_label(@landing.params)}
        class="rounded-full bg-neutral-200/70 px-2 py-0.5 text-neutral-800"
      >
        {campaign_label(@landing.params)}
      </span>
      <span :if={@landing && referrer_host(@landing.referrer)} title={@landing.referrer}>
        from {referrer_host(@landing.referrer)}
      </span>
      <span :if={@landing}>
        landed on <code class="font-mono text-neutral-600">{@landing.path}</code>
        at {timestamp(@landing.at)}
      </span>
      <details class="basis-full">
        <summary class="cursor-pointer select-none hover:text-neutral-800">Visit details</summary>
        <dl class="mt-2 grid grid-cols-[max-content_minmax(0,1fr)] gap-x-4 gap-y-1 font-mono text-xs">
          <%= for {name, value} <- Enum.sort(if(@landing, do: @landing.params, else: %{})) do %>
            <dt class="text-neutral-500">{name}</dt>
            <dd class="break-all text-neutral-800">{value}</dd>
          <% end %>
          <dt :if={@landing && @landing.referrer} class="text-neutral-500">referrer</dt>
          <dd :if={@landing && @landing.referrer} class="break-all text-neutral-800">
            {@landing.referrer}
          </dd>
          <%= for {name, value} <- Enum.sort(@headers) do %>
            <dt class="text-neutral-500">{name}</dt>
            <dd class="break-all text-neutral-800">{value}</dd>
          <% end %>
        </dl>
      </details>
    </div>
    """
  end

  attr :context, Context, required: true
  attr :id, :string, required: true
  attr :channel, :string, required: true
  attr :viewport, :map, default: nil

  # The frame renders at the recorded viewport, scaled down to fit: the
  # FrameViewport hook writes the sizes into the ignored style element, so
  # the frame itself stays server-rendered.
  defp frame(assigns) do
    ~H"""
    <section
      id="replay-viewport"
      phx-hook="FrameViewport"
      data-width={@viewport && @viewport.width}
      data-height={@viewport && @viewport.height}
      class="mb-4 overflow-hidden rounded-lg border border-neutral-200 bg-white"
    >
      <style id="replay-viewport-style" phx-update="ignore">
      </style>
      <div id="replay-viewport-box">
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

  defp position(_at, 0), do: 0
  defp position(at, duration_ms), do: Float.round(at / duration_ms * 100, 3)

  @impl true
  def render(%{recording: nil} = assigns) do
    ~H"""
    <main class="mx-auto max-w-6xl px-4 py-6">
      <.flash_error flash={@flash} />
      <header class="mb-4">
        <.link
          navigate={Context.path(@context, [])}
          class="text-sm text-neutral-500 hover:text-neutral-800"
        >
          ← Recordings
        </.link>
        <h1 class="mt-1 text-xl font-semibold">Live session</h1>
        <p :if={@load_error?} role="alert" class="text-sm text-red-700">
          Could not redact this session, so it is not shown.
        </p>
        <div
          :if={!@load_error?}
          id="replay-redaction"
          role="status"
          class="mt-2 max-w-md text-sm text-neutral-500"
        >
          <p>{redaction_label(@progress)}</p>
          <div class="mt-2 h-1 rounded-full bg-neutral-200">
            <div
              class="h-1 rounded-full bg-neutral-900 transition-[width]"
              style={"width: #{redaction_percent(@progress)}%"}
            >
            </div>
          </div>
        </div>
      </header>
      <.frame :if={!@load_error?} context={@context} id={@id} channel={@channel} />
    </main>
    """
  end

  def render(assigns) do
    ~H"""
    <main class="mx-auto max-w-6xl px-4 py-6">
      <.flash_error flash={@flash} />
      <header class="mb-4">
        <div class="flex items-center justify-between gap-3">
          <.link
            navigate={Context.path(@context, [])}
            class="text-sm text-neutral-500 hover:text-neutral-800"
          >
            ← Recordings
          </.link>
          <.button variant="danger" phx-click="delete" data-confirm="Delete this recording?">
            Delete recording
          </.button>
        </div>
        <h1 class="mt-1 text-xl font-semibold">{inspect(@recording.view)}</h1>
        <p class="text-sm text-neutral-500 tabular-nums">
          Session <code class="font-mono text-neutral-600">{String.slice(@recording.id, 0, 12)}</code>
          · {length(@recording.events)} events · {clock(@duration_ms)}
          <span :if={@error_count > 0} class="text-red-700">
            · {@error_count} {if @error_count == 1, do: "error", else: "errors"}
          </span>
          <span :if={@dropped > 0} title={inspect(@recording.dropped)}>
            · {@dropped} collected events over the limit dropped
          </span>
        </p>
        <p
          :if={@viewport || @recording.client.user_agent || @recording.client.referer || @journey}
          class="mt-1 flex flex-wrap items-center gap-x-3 gap-y-1 text-sm text-neutral-500"
        >
          <span :if={@viewport} id="replay-device" title={@recording.client.user_agent}>
            {viewport_label(@viewport)}<span :if={label = device_label(@recording.client.user_agent)}> · {label}</span>
          </span>
          <span :if={!@viewport && @recording.client.user_agent} title={@recording.client.user_agent}>
            {device_label(@recording.client.user_agent) || "Unknown browser"}
          </span>
          <span :if={@recording.client.referer} title={@recording.client.referer}>
            Came from
            <code class="font-mono text-neutral-600">{path_of(@recording.client.referer)}</code>
          </span>
          <span :if={@journey} id="replay-journey" class="inline-flex items-center gap-2">
            <.link
              navigate={Context.path(@context, []) <> "?" <> URI.encode_query(%{"tab" => @journey.tab})}
              class="underline decoration-neutral-300 hover:text-neutral-800"
            >
              Session {@journey.position} of {@journey.total} in this tab
            </.link>
            <.link
              :if={@journey.previous}
              navigate={Context.path(@context, [@journey.previous.id])}
              class="hover:text-neutral-800"
            >
              ← Previous
            </.link>
            <.link
              :if={@journey.next}
              navigate={Context.path(@context, [@journey.next.id])}
              class="hover:text-neutral-800"
            >
              Next →
            </.link>
          </span>
        </p>
        <.visit client={@recording.client} />
      </header>

      <section class="mb-4 rounded-lg border border-neutral-200 bg-white p-4">
        <div class="mb-3 flex items-center gap-1.5">
          <.button phx-click="previous" aria-label="Previous event" disabled={@index == 0}>
            ⏮
          </.button>
          <.button phx-click="toggle" aria-label={if @playing, do: "Pause", else: "Play"}>
            {if @playing, do: "⏸", else: "▶"}
          </.button>
          <.button
            phx-click="next"
            aria-label="Next event"
            disabled={@index == length(@recording.events) - 1}
          >
            ⏭
          </.button>
          <span class="ml-2 font-mono text-xs text-neutral-500 tabular-nums">
            {clock(@at)} / {clock(@duration_ms)}
          </span>
          <span class="flex-1"></span>
          <form id="replay-speed-form" phx-change="speed">
            <label class="sr-only" for="replay-speed">Playback speed</label>
            <select
              id="replay-speed"
              name="speed"
              class="rounded-md border border-neutral-200 bg-white px-2 py-1 font-mono text-xs"
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
          <div class="relative h-1 flex-1 rounded-full bg-neutral-200">
            <span
              :for={event <- @recording.events}
              class={[
                "absolute top-1/2 -translate-x-1/2 -translate-y-1/2 rounded-full",
                marker_class(event)
              ]}
              style={"left: #{position(event.at, @duration_ms)}%"}
              title={event_label(event)}
            ></span>
          </div>
          <span
            data-thumb
            class="absolute top-1/2 size-3.5 -translate-x-1/2 -translate-y-1/2 rounded-full border-2 border-white bg-neutral-900 shadow-sm"
            style={"left: #{position(@at, @duration_ms)}%"}
          ></span>
        </div>
      </section>

      <.frame context={@context} id={@recording.id} channel={@channel} viewport={@viewport} />

      <div class="grid grid-cols-1 gap-4 lg:grid-cols-2">
        <section class="flex min-w-0 flex-col rounded-lg border border-neutral-200 bg-white">
          <h2 class="flex items-center justify-between gap-2 border-b border-neutral-100 px-4 py-2.5 text-xs font-medium tracking-wide text-neutral-500 uppercase">
            Events <span class="flex-1"></span>
            <button
              :for={kind <- @kinds}
              :if={length(@kinds) > 1}
              type="button"
              phx-click="toggle_kind"
              phx-value-kind={kind}
              aria-pressed={to_string(not MapSet.member?(@hidden, kind))}
              class={[
                "rounded-full border px-2 py-0.5 normal-case tracking-normal",
                MapSet.member?(@hidden, kind) && "border-neutral-200 text-neutral-400 line-through",
                not MapSet.member?(@hidden, kind) && "border-neutral-300 text-neutral-700"
              ]}
            >
              {kind_label(kind)}
            </button>
            <span class="tabular-nums text-neutral-400">{length(@recording.events)}</span>
          </h2>
          <ol
            id="replay-events"
            phx-hook="EventList"
            class="relative max-h-[clamp(300px,40vh,600px)] overflow-y-auto overscroll-contain p-1.5"
          >
            <li
              :for={{event, index} <- Enum.with_index(@recording.events)}
              :if={not MapSet.member?(@hidden, event_kind(event.type))}
            >
              <button
                type="button"
                phx-click="seek"
                phx-value-index={index}
                aria-current={index == @index && "step"}
                class={[
                  "flex w-full min-w-0 items-center gap-2 rounded-md px-2.5 py-1.5 text-left text-[13px]",
                  collected?(event) && "pl-7 text-xs",
                  index == @index && "bg-neutral-900 text-white",
                  index != @index && "hover:bg-neutral-50",
                  index > @index && "text-neutral-400",
                  index < @index && Event.error?(event) && "text-red-700"
                ]}
              >
                <span class="shrink-0">{event_icon(event.type)}</span>
                <span class="min-w-0 flex-1 truncate">{event_label(event)}</span>
                <span
                  :if={duration = Event.duration(event)}
                  class="shrink-0 font-mono text-[11px] tabular-nums opacity-60"
                >
                  {milliseconds(duration)}
                </span>
                <span class="shrink-0 font-mono text-[11px] tabular-nums opacity-60">{clock(event.at)}</span>
              </button>
            </li>
          </ol>
        </section>

        <section class="flex min-w-0 flex-col rounded-lg border border-neutral-200 bg-white">
          <div
            :if={@event && @event.type in [:telemetry, :log, :exit]}
            class="border-b border-neutral-100"
          >
            <h2 class="border-b border-neutral-100 px-4 py-2.5 text-xs font-medium tracking-wide text-neutral-500 uppercase">
              Details
            </h2>
            <pre class="max-h-60 overflow-auto p-4 font-mono text-xs leading-relaxed break-words whitespace-pre-wrap text-neutral-700">{inspect(@event.data, pretty: true, limit: 50)}</pre>
          </div>
          <h2 class="border-b border-neutral-100 px-4 py-2.5 text-xs font-medium tracking-wide text-neutral-500 uppercase">
            Assigns
          </h2>
          <pre class="max-h-[clamp(300px,40vh,600px)] overflow-auto p-4 font-mono text-xs leading-relaxed break-words whitespace-pre-wrap text-neutral-700">{@assigns_preview}</pre>
        </section>
      </div>
    </main>
    """
  end
end
