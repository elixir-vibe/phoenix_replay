defmodule PhoenixReplay.Web.Live.Frame do
  @moduledoc """
  Re-renders a recorded view with its recorded assigns.

  Loaded in an iframe by the player and driven through
  `PhoenixReplay.Web.Playback`. Recorded assigns are assigned directly, so
  the recorded template renders unchanged. Frame state lives in
  `socket.private`, except for the single `:phoenix_replay_frame` assign that
  the layout and the fallback template need.

  HEEx evaluates assigns lazily, while LiveView computes the diff. A
  template that fails with the recorded assigns would crash the frame, so
  each position is rendered once up front and a placeholder is shown instead
  when that fails.
  """

  use Phoenix.LiveView

  require Logger

  alias PhoenixReplay.Recording.Timeline
  alias PhoenixReplay.Web.{Context, Layouts, Playback}
  alias Phoenix.LiveView.{Comprehension, Rendered}

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
  def render(%{@private => %{error: nil, view: view}} = assigns), do: view.render(assigns)

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
    recorded = Timeline.assigns_at(recording, Timeline.clamp(recording, index))
    {flash, recorded} = Map.pop(recorded, :flash, %{})
    recorded = Map.drop(recorded, @unassignable)
    keys = Map.keys(recorded)

    socket
    |> assign(Map.new(previous_keys -- keys, &{&1, nil}))
    |> assign(recorded)
    |> replace_flash(flash)
    |> put_private(@private, %{recording: recording, keys: keys})
    |> check_render()
  end

  defp replace_flash(socket, flash) do
    Enum.reduce(flash, clear_flash(socket), fn {kind, message}, acc ->
      put_flash(acc, kind, message)
    end)
  end

  defp check_render(socket) do
    frame = socket.assigns[@private]
    assign(socket, @private, %{frame | error: render_error(frame.view, socket.assigns)})
  end

  # credo:disable-for-next-line ExSlop.Check.Warning.BlanketRescue
  defp render_error(view, assigns) do
    assigns |> view.render() |> evaluate()
    nil
  rescue
    # reach:disable-next-line bare_rescue -- recorded templates are foreign code rendered with partial assigns
    exception ->
      Logger.debug(
        "PhoenixReplay: #{inspect(view)} failed to render: #{Exception.message(exception)}"
      )

      Exception.message(exception)
  end

  defp evaluate(%Rendered{dynamic: dynamic}), do: Enum.each(dynamic.(false), &evaluate/1)

  defp evaluate(%Comprehension{entries: entries}) do
    Enum.each(entries, fn {_key, _vars, render} ->
      Enum.each(render.(%{}, false), &evaluate/1)
    end)
  end

  defp evaluate(_dynamic), do: :ok
end
