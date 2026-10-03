defmodule PhoenixReplay.Web.Live.Show do
  @moduledoc """
  Plays back a recording.

  Playback is driven by the server: each step schedules the next one after
  the recorded gap divided by the speed, and tells the frame which event to
  show through `PhoenixReplay.Web.Playback`. The `Scrubber` hook only maps
  pointer positions to events and animates the thumb between them.
  """

  use Phoenix.LiveView

  import PhoenixReplay.Web.Components

  alias PhoenixReplay.Recording.Timeline
  alias PhoenixReplay.Recordings
  alias PhoenixReplay.Web.{Context, Layouts, Playback}

  @speeds [1, 2, 5, 10]

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    context = Context.fetch(socket)
    recording = Context.fetch_recording!(socket, id)
    channel = Playback.new_channel()
    if connected?(socket), do: Playback.subscribe(channel)

    {:ok,
     socket
     |> assign(
       page_title: "Replay · #{inspect(recording.view)}",
       assets: Layouts.dashboard_assets(context),
       context: context,
       recording: recording,
       channel: channel,
       duration_ms: Timeline.duration_ms(recording),
       speed: 1,
       playing: nil,
       speeds: @speeds
     )
     |> seek(Timeline.first_render_index(recording))}
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

  def handle_info({Playback, :frame_ready}, socket) do
    :ok = Playback.seek(socket.assigns.channel, socket.assigns.index)
    {:noreply, socket}
  end

  defp seek(socket, index) do
    %{recording: recording, channel: channel} = socket.assigns
    index = Timeline.clamp(recording, index)
    :ok = Playback.seek(channel, index)

    assign(socket,
      index: index,
      at: event_at(recording, index),
      next_at: event_at(recording, min(index + 1, Timeline.last_index(recording))),
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

  defp position(_at, 0), do: 0
  defp position(at, duration_ms), do: Float.round(at / duration_ms * 100, 3)

  @impl true
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
        </p>
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
                marker_class(event.type)
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

      <section class="mb-4 overflow-hidden rounded-lg border border-neutral-200 bg-white">
        <iframe
          id="replay-frame"
          title="Replay"
          src={Context.path(@context, [@recording.id, "frame"]) <> "?channel=#{@channel}"}
          class="block h-[600px] w-full border-0"
        ></iframe>
      </section>

      <div class="grid grid-cols-1 gap-4 lg:grid-cols-2">
        <section class="flex min-w-0 flex-col rounded-lg border border-neutral-200 bg-white">
          <h2 class="flex items-center justify-between border-b border-neutral-100 px-4 py-2.5 text-xs font-medium tracking-wide text-neutral-500 uppercase">
            Events <span class="tabular-nums text-neutral-400">{length(@recording.events)}</span>
          </h2>
          <ol
            id="replay-events"
            phx-hook="EventList"
            class="relative max-h-[clamp(300px,40vh,600px)] overflow-y-auto overscroll-contain p-1.5"
          >
            <li :for={{event, index} <- Enum.with_index(@recording.events)}>
              <button
                type="button"
                phx-click="seek"
                phx-value-index={index}
                aria-current={index == @index && "step"}
                class={[
                  "flex w-full min-w-0 items-center gap-2 rounded-md px-2.5 py-1.5 text-left text-[13px]",
                  index == @index && "bg-neutral-900 text-white",
                  index != @index && "hover:bg-neutral-50",
                  index > @index && "text-neutral-400"
                ]}
              >
                <span class="shrink-0">{event_icon(event.type)}</span>
                <span class="min-w-0 flex-1 truncate">{event_label(event)}</span>
                <span class="shrink-0 font-mono text-[11px] tabular-nums opacity-60">{clock(event.at)}</span>
              </button>
            </li>
          </ol>
        </section>

        <section class="flex min-w-0 flex-col rounded-lg border border-neutral-200 bg-white">
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
