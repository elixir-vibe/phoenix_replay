defmodule PhoenixReplay.Web.Live.Frame do
  @moduledoc """
  Re-renders a recorded view with its recorded assigns.

  Loaded in an iframe by the player and driven through
  `PhoenixReplay.Web.Player.Channel`. Recorded assigns are assigned directly, so
  the recorded template renders unchanged. Frame state lives in
  `socket.private`, except for the single `:phoenix_replay_frame` assign that
  the layout and the fallback template need.

  A view whose live render depends on code in the browser can define
  `replay_render/1`, which the frame calls in place of `render/1`; see
  `PhoenixReplay.Web.Rendering.render/2`.

  Opened with `stage=1`, as `PhoenixReplay.Web.Export.Stage` opens it, the
  frame pushes a `"phx_replay:shown"` event with the index after each
  render, so the export takes its screenshot once the page shows it.

  Form control values the browser recorded are pushed to the frame's
  script with a `"phx_replay:inputs"` event after each render, which puts
  them back into the replayed page; see `PhoenixReplay.Recording.State`.
  So is the root layout rendered again with the replayed assigns, with
  `"phx_replay:root"`, whose `<html>` and `<body>` attributes the script
  copies, as the page's root layout renders only once.

  LiveComponents in the template render through
  `PhoenixReplay.Web.Live.ReplayComponent` with their recorded assigns; see
  `PhoenixReplay.Web.Rendering`. A template that fails with the recorded
  assigns shows a placeholder instead of crashing the frame.

  A session that is still running is never read from the buffer here: the
  player redacts it and hands it over with `PhoenixReplay.Web.Player.Channel.load/2`.
  Until then the frame shows a placeholder.
  """

  use Phoenix.LiveView

  alias PhoenixReplay.{Migration, Replay}
  alias PhoenixReplay.Recording.{State, Timeline}
  alias PhoenixReplay.Catalog
  alias PhoenixReplay.Web.{Context, Layouts, Rendering}
  alias PhoenixReplay.Web.Player.Channel
  alias PhoenixReplay.Web.Live.ReplayComponent

  @private :phoenix_replay_frame
  @stage :phoenix_replay_stage
  @channel :phoenix_replay_channel
  # No root layout or attributes to send, as a frame starts.
  @no_root %{layout: nil, attributes: %{}}
  # Assigns rendered as nil when the recording lacks them, at most.
  @max_unrecorded 5

  @impl true
  def mount(%{"id" => id} = params, _session, socket) do
    # Indexed like the player's.
    recording =
      if Catalog.live?(id),
        do: nil,
        else: socket |> Context.fetch_recording!(id) |> Timeline.for_playback() |> elem(0)

    if connected?(socket) and is_binary(params["channel"]) do
      :ok = Channel.subscribe(params["channel"])
      :ok = Channel.frame_ready(params["channel"])
    end

    context = Context.fetch(socket)

    frame = %{
      view: recording && recording.view,
      assets: Layouts.frame_assets(context, context.endpoint || socket.endpoint),
      components: %{},
      error: nil
    }

    {:ok,
     socket
     |> put_private(@stage, params["stage"] == "1")
     |> put_private(@channel, if(is_binary(params["channel"]), do: params["channel"]))
     |> put_private(@private, private(recording))
     |> assign(@private, frame)
     |> show_first(), layout: false}
  end

  defp show_first(%{private: %{@private => %{recording: nil}}} = socket), do: socket

  defp show_first(socket),
    do: show(socket, Timeline.first_render_index(socket.private[@private].recording))

  # Recorded templates keep their bindings; the replay must not react to them.
  @impl true
  def handle_event(_event, _params, socket), do: {:noreply, socket}

  @impl true
  def handle_info({Channel, {:load, recording}}, socket) do
    if Context.allowed?(socket, :view, recording) do
      {:noreply,
       socket
       |> put_private(@private, private(recording))
       |> update(@private, &%{&1 | view: recording.view})
       |> show_first()}
    else
      {:noreply, socket}
    end
  end

  def handle_info(
        {Channel, {:seek, _index}},
        %{private: %{@private => %{recording: nil}}} = socket
      ),
      do: {:noreply, socket}

  def handle_info({Channel, {:seek, index}}, socket), do: {:noreply, show(socket, index)}
  def handle_info({Channel, _message}, socket), do: {:noreply, socket}

  @impl true
  def render(%{@private => %{view: nil}} = assigns) do
    ~H"""
    <div style="padding: 2rem; color: #737373; text-align: center; font-family: system-ui, sans-serif;">
      Redacting the session…
    </div>
    """
  end

  def render(%{@private => %{error: nil, view: view, components: states}} = assigns),
    do: view |> Rendering.render(assigns) |> Rendering.rewrite(states)

  def render(assigns) do
    ~H"""
    <div style="padding: 2rem; color: #737373; text-align: center; font-family: system-ui, sans-serif;">
      <p>Could not render {inspect(@phoenix_replay_frame.view)} at this point.</p>
      <p style="font-size: 0.875rem;">{@phoenix_replay_frame.error}</p>
    </div>
    """
  end

  defp private(nil),
    do: %{recording: nil, timeline: nil, migrations: [], keys: [], inputs: %{}, root: @no_root}

  defp private(recording),
    do: %{
      recording: recording,
      timeline: Timeline.new(recording),
      # The app's migrations newer than the recording, applied at each moment.
      migrations: Migration.pending(Migration.all(recording.view), migrated(recording)),
      keys: [],
      inputs: %{},
      root: @no_root
    }

  defp migrated(%{code: %{migration: version}}), do: version
  defp migrated(_recording), do: nil

  defp show(socket, index) do
    %{timeline: timeline, keys: previous_keys, migrations: migrations} =
      private = socket.private[@private]

    timeline = Timeline.seek(timeline, index)
    {flash, recorded} = Map.pop(timeline.assigns, :flash, %{})
    %{view: view} = socket.assigns[@private]
    recorded = Migration.apply_to(migrations, view, Rendering.assignable(recorded))

    states =
      Map.new(timeline.components, fn {{module, _id} = key, assigns} ->
        {key, Migration.apply_to(migrations, module, assigns)}
      end)

    keys = Map.keys(recorded)

    socket
    |> assign(Map.new(previous_keys -- keys, &{&1, nil}))
    |> assign(recorded)
    |> replace_flash(flash)
    |> update(@private, &%{&1 | components: states})
    |> refresh_components(states)
    |> put_private(@private, %{private | timeline: timeline, keys: keys})
    |> check_render()
    |> push_inputs(State.inputs(timeline.assigns[State.assign()]))
    |> push_root()
    |> push_shown(index)
  end

  defp push_shown(%{private: %{@stage => true}} = socket, index),
    do: push_event(socket, "phx_replay:shown", %{index: index})

  defp push_shown(socket, _index), do: socket

  # The values typed into form controls are not in the assigns; the frame's
  # script puts them back after LiveView applied the render.
  defp push_inputs(%{private: %{@private => %{inputs: inputs}}} = socket, inputs), do: socket

  defp push_inputs(socket, inputs) do
    socket
    |> push_event("phx_replay:inputs", %{values: inputs})
    |> put_private(@private, %{socket.private[@private] | inputs: inputs})
  end

  # The root layout renders once, but an app's layout can make `<html>` and
  # `<body>` follow its assigns, such as a theme. So it is rendered again
  # with each moment's assigns, and sent when it changed; the frame's
  # script copies those attributes onto the page. A layout that cannot
  # render outside a request, such as one reading `@conn`, sends nothing.
  defp push_root(socket) do
    root = %{layout: root_layout(socket), attributes: root_attributes(socket)}

    case socket.private[@private] do
      %{root: ^root} ->
        socket

      private ->
        socket
        |> push_event("phx_replay:root", root)
        |> put_private(@private, %{private | root: root})
    end
  end

  # credo:disable-for-next-line ExSlop.Check.Warning.BlanketRescue
  defp root_layout(socket) do
    case app_layout(socket) do
      {module, function} ->
        assigns = Map.merge(socket.assigns, %{inner_content: "", live_module: __MODULE__})

        module
        |> apply(function, [assigns])
        |> Phoenix.HTML.Safe.to_iodata()
        |> IO.iodata_to_binary()

      nil ->
        nil
    end
  rescue
    # The app's layout is foreign code, rendered without `@conn` and with partial assigns.
    # reach:disable-next-line bare_rescue -- foreign layout code rendered with partial assigns
    _exception -> nil
  end

  # The app's own root layout, when the frame renders in one: the
  # dashboard's, whose attributes never change, has nothing to send.
  defp app_layout(socket) do
    context = Context.fetch(socket)

    case context.frame_layout do
      {Layouts, :frame} -> nil
      layout -> layout
    end
  end

  defp root_attributes(socket) do
    %{view: view} = socket.assigns[@private]
    Replay.root_attributes(Context.fetch(socket).config.replay, view, socket.assigns)
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
      Enum.each(states, fn {{module, id}, _assigns} ->
        send_update(ReplayComponent, id: {module, id}, __replay_states__: states)
      end)
    end

    socket
  end

  # An assign the template reads but the recording lacks, such as one a
  # newer template reads in an older recording, is rendered as nil, which
  # most templates take as unset, and the player is told which. One filled
  # before stays nil, and unrecorded, until the recording sets it.
  defp check_render(socket) do
    frame = socket.assigns[@private]
    %{keys: recorded} = private = socket.private[@private]
    carried = Enum.reject(private[:unrecorded] || [], &(&1 in recorded))
    {socket, unrecorded, error} = fill_unrecorded(socket, frame.view, Enum.reverse(carried))

    socket
    |> assign(@private, %{frame | error: error})
    |> tell_unrecorded(Enum.reverse(unrecorded))
  end

  defp fill_unrecorded(socket, view, unrecorded) do
    case Rendering.render_check(view, socket.assigns) do
      :ok ->
        {socket, unrecorded, nil}

      {:missing, key} ->
        if length(unrecorded) < @max_unrecorded and key not in unrecorded,
          do: fill_unrecorded(assign(socket, key, nil), view, [key | unrecorded]),
          else: {socket, unrecorded, "the recording has no @#{key}"}

      {:error, description} ->
        {socket, unrecorded, description}
    end
  end

  defp tell_unrecorded(%{private: %{@channel => channel}} = socket, unrecorded)
       when is_binary(channel) do
    if socket.private[@private][:unrecorded] != unrecorded,
      do: :ok = Channel.unrecorded(channel, unrecorded)

    put_private(socket, @private, Map.put(socket.private[@private], :unrecorded, unrecorded))
  end

  defp tell_unrecorded(socket, _unrecorded), do: socket
end
