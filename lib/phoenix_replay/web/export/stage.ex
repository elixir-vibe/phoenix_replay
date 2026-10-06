defmodule PhoenixReplay.Web.Export.Stage do
  @moduledoc """
  The page the export browser films: the replay frame at the recorded
  viewport, centred on a dark canvas, with the player's pointer overlay
  over it and nothing else.

  It drives its frame as the player does, over a private
  `PhoenixReplay.Web.Player.Channel`: the frame is rendered once the stage
  has subscribed, so its announcement is never missed, and the stage passes
  it on to the `ExportStage` hook as `"phx_replay:frame_ready"`. The hook
  asks for each event with `"seek"`. `PhoenixReplay.Export.Screenshots`
  only calls the hook, `window.phoenixReplayStage`, to wait for the frame
  and to show each moment before its screenshot.

  `pointer=false` hides the pointer while the page still scrolls as
  recorded; `rotated=true` turns both off, as the player does when rotated.
  """

  use Phoenix.LiveView

  alias PhoenixReplay.Recording.{Client, PointerTrack, Timeline}
  alias PhoenixReplay.Web.{Context, Layouts}
  alias PhoenixReplay.Web.Export.Access
  alias PhoenixReplay.Web.Player.Channel

  @impl true
  def mount(%{"token" => token} = params, _session, socket) do
    context = Context.fetch(socket)
    id = Access.recording_id(socket)
    recording = Context.fetch_recording!(socket, id)
    {_playback, track} = Timeline.for_playback(recording)
    channel = Channel.new()

    frame_src =
      if connected?(socket) do
        :ok = Channel.subscribe(channel)
        query = URI.encode_query(channel: channel, stage: 1)
        Context.path(context, ["frame", token, id]) <> "?" <> query
      end

    {:ok,
     assign(socket,
       assets: Layouts.dashboard_assets(context),
       page_title: "Replay",
       channel: channel,
       frame_src: frame_src,
       viewport: recording.client.viewport || Client.default_viewport(),
       track: track,
       pointer?: PointerTrack.any?(track),
       hidden?: params["pointer"] == "false",
       rotated?: params["rotated"] == "true"
     ), layout: false}
  end

  @impl true
  def handle_event("seek", %{"index" => index}, socket) when is_integer(index) do
    :ok = Channel.seek(socket.assigns.channel, index)
    {:noreply, socket}
  end

  @impl true
  def handle_info({Channel, :frame_ready}, socket),
    do: {:noreply, push_event(socket, "phx_replay:frame_ready", %{})}

  def handle_info({Channel, _message}, socket), do: {:noreply, socket}

  # Nothing re-renders the stage once it is connected, so the sizes the
  # hook sets on the device stay.
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
        style={"position: absolute; left: 0; top: 0; width: #{@viewport.width}px; height: #{@viewport.height}px;"}
      >
        <iframe
          :if={@frame_src}
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
          data-follow-scroll
          data-rotated={@rotated?}
          data-track={JSON.encode!(@track)}
          data-trail={PointerTrack.trail_ms()}
          data-ripple={PointerTrack.ripple_ms()}
          data-width={@viewport.width}
          data-height={@viewport.height}
          style={"position: absolute; inset: 0; pointer-events: none; visibility: #{if @hidden?, do: "hidden", else: "visible"};"}
        >
        </div>
      </div>
    </div>
    """
  end
end
