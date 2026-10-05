defmodule PhoenixReplay.Export.Stage do
  @moduledoc """
  The page the export browser films: the replay frame at the recorded
  viewport, centred on a dark canvas, with the player's pointer overlay
  over it and nothing else.

  `PhoenixReplay.Export.Capture` drives the frame through
  `PhoenixReplay.Web.Player.Channel`, like the player does, and calls
  `window.phoenixReplayStage.show/1`, set up by the `ExportStage` hook,
  to size the frame, wait for the event to render and move the pointer to
  the moment before each screenshot.
  """

  use Phoenix.LiveView

  alias PhoenixReplay.Export.Access
  alias PhoenixReplay.Recording.{PointerTrack, Timeline}
  alias PhoenixReplay.Web.{Context, Layouts}

  @default_viewport %{width: 1280, height: 800}

  @impl true
  def mount(%{"token" => token} = params, _session, socket) do
    context = Context.fetch(socket)
    id = Access.recording_id(socket)
    recording = Context.fetch_recording!(socket, id)
    {_playback, track} = Timeline.for_playback(recording)
    query = URI.encode_query(channel: params["channel"] || "", stage: 1)

    {:ok,
     assign(socket,
       assets: Layouts.dashboard_assets(context),
       page_title: "Replay",
       frame_src: Context.path(context, ["frame", token, id]) <> "?" <> query,
       viewport: recording.client.viewport || @default_viewport,
       track: track,
       pointer?: PointerTrack.any?(track)
     ), layout: false}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div
      id="replay-stage"
      phx-hook="ExportStage"
      style="position: fixed; inset: 0; overflow: hidden; background: #0a0a0a;"
    >
      <div
        id="replay-stage-device"
        phx-update="ignore"
        style={"position: absolute; left: 0; top: 0; width: #{@viewport.width}px; height: #{@viewport.height}px;"}
      >
        <iframe
          id="replay-frame"
          title="Replay"
          src={@frame_src}
          style="display: block; width: 100%; height: 100%; border: 0; background: #fff;"
        ></iframe>
        <div
          :if={@pointer?}
          id="replay-pointer"
          phx-hook="Pointer"
          phx-update="ignore"
          data-frame-overlay
          data-track={JSON.encode!(@track)}
          data-width={@viewport.width}
          data-height={@viewport.height}
          style="position: absolute; inset: 0; pointer-events: none;"
        >
        </div>
      </div>
    </div>
    """
  end
end
