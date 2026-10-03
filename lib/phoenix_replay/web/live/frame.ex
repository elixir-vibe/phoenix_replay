defmodule PhoenixReplay.Web.Live.Frame do
  @moduledoc """
  Re-renders a recorded view with its recorded assigns.

  Loaded in an iframe by the player and driven through
  `PhoenixReplay.Web.Playback`. Recorded assigns are assigned directly, so
  the recorded template renders unchanged. Frame state lives in
  `socket.private`, except for the single `:phoenix_replay_frame` assign that
  the layout and the fallback template need.

  LiveComponents in the template render through
  `PhoenixReplay.Web.Live.ReplayComponent` with their recorded assigns; see
  `PhoenixReplay.Web.Replay`. A template that fails with the recorded
  assigns shows a placeholder instead of crashing the frame.
  """

  use Phoenix.LiveView

  alias PhoenixReplay.Recording.Timeline
  alias PhoenixReplay.Web.{Context, Layouts, Playback, Replay}
  alias PhoenixReplay.Web.Live.ReplayComponent

  @private :phoenix_replay_frame
  @unassignable [:flash, :uploads, :streams, :socket, :myself]

  @impl true
  def mount(%{"id" => id} = params, _session, socket) do
    recording = Context.fetch_recording!(socket, id)

    if connected?(socket) and is_binary(params["channel"]) do
      :ok = Playback.subscribe(params["channel"])
      :ok = Playback.frame_ready(params["channel"])
    end

    frame = %{
      view: recording.view,
      assets: Layouts.frame_assets(Context.fetch(socket), socket.endpoint),
      components: %{},
      error: nil
    }

    {:ok,
     socket
     |> put_private(@private, %{recording: recording, keys: []})
     |> assign(@private, frame)
     |> show(Timeline.first_render_index(recording)), layout: false}
  end

  # Recorded templates keep their bindings; the replay must not react to them.
  @impl true
  def handle_event(_event, _params, socket), do: {:noreply, socket}

  @impl true
  def handle_info({Playback, {:seek, index}}, socket), do: {:noreply, show(socket, index)}
  def handle_info({Playback, _message}, socket), do: {:noreply, socket}

  @impl true
  def render(%{@private => %{error: nil, view: view, components: states}} = assigns),
    do: assigns |> view.render() |> Replay.rewrite(states)

  def render(assigns) do
    ~H"""
    <div style="padding: 2rem; color: #737373; text-align: center; font-family: system-ui, sans-serif;">
      <p>Could not render {inspect(@phoenix_replay_frame.view)} at this point.</p>
      <p style="font-size: 0.875rem;">{@phoenix_replay_frame.error}</p>
    </div>
    """
  end

  defp show(socket, index) do
    %{recording: recording, keys: previous_keys} = socket.private[@private]
    index = Timeline.clamp(recording, index)
    recorded = Timeline.assigns_at(recording, index)
    states = Timeline.components_at(recording, index)
    {flash, recorded} = Map.pop(recorded, :flash, %{})
    recorded = Map.drop(recorded, @unassignable)
    keys = Map.keys(recorded)

    socket
    |> assign(Map.new(previous_keys -- keys, &{&1, nil}))
    |> assign(recorded)
    |> replace_flash(flash)
    |> update(@private, &%{&1 | components: states})
    |> refresh_components(states)
    |> put_private(@private, %{recording: recording, keys: keys})
    |> check_render()
  end

  defp replace_flash(socket, flash) do
    Enum.reduce(flash, clear_flash(socket), fn {kind, message}, acc ->
      put_flash(acc, kind, message)
    end)
  end

  # Components whose parent template did not change are not re-rendered, so
  # they get their recorded assigns directly.
  defp refresh_components(socket, states) do
    if connected?(socket) do
      for {module, id} <- Map.keys(states),
          do: send_update(ReplayComponent, id: {module, id}, __replay_states__: states)
    end

    socket
  end

  defp check_render(socket) do
    frame = socket.assigns[@private]
    assign(socket, @private, %{frame | error: Replay.render_error(frame.view, socket.assigns)})
  end
end
