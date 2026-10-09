defmodule PhoenixReplay.Recorder do
  @moduledoc """
  `on_mount` hook that records LiveView sessions.

      live_session :default, on_mount: [PhoenixReplay.Recorder] do
        live "/dashboard", DashboardLive
      end

  Options given as `{PhoenixReplay.Recorder, opts}` override the
  `PhoenixReplay.Config` values for that live session. `:sample_rate`,
  `:keep`, `:max_events`, `:sanitizer`, `:redact`, `:flush`, `:pointer` and
  `:state` are accepted:

      live_session :checkout,
        on_mount: [{PhoenixReplay.Recorder, keep: [rate: 0.1, errors: true]}] do
        live "/checkout", CheckoutLive
      end

  Recording starts on the connected mount. Lifecycle hooks capture events,
  params changes, `handle_info/2` message tags, and the assigns changed by
  each render, all passed through the configured `PhoenixReplay.Sanitizer`.
  While `:max_memory` is exceeded, new sessions are not recorded.
  Events are written by the LiveView process itself into
  `PhoenixReplay.Session.Buffer`; `PhoenixReplay.Session.Monitor` saves the
  recording once the process exits.

  Recorder state lives in `socket.private`, so the view's assigns are left
  untouched.

  When the host app sends PhoenixReplay's client context, the recording
  also holds the browser's viewport, user agent, tab and the URL the user
  came from; see `PhoenixReplay.Capture.Browser`.

  On the connected mount of a recorded session, the recorder pushes a
  `"phx_replay:record"` event with what the browser should record:
  `%{pointer: settings | nil, state: settings | nil}`. The client module's
  `replayRecorder/1` starts on it and sends pointer batches and client
  state back, which the recorder records and halts; see
  `PhoenixReplay.Capture.Pointer` and `PhoenixReplay.Capture.State`.
  """

  import Phoenix.LiveView,
    only: [
      attach_hook: 4,
      connected?: 1,
      get_connect_info: 2,
      get_connect_params: 1,
      push_event: 3,
      put_private: 3
    ]

  alias PhoenixReplay.{Config, Migration, Recording}
  alias PhoenixReplay.Capture.{Assigns, Browser, Pointer, State}
  alias PhoenixReplay.Session.{Buffer, Monitor, Visits}

  @private :phoenix_replay
  # Where PhoenixReplay.Plug keeps the visit in the session.
  @kept PhoenixReplay.Plug.session_key()
  @record_event "phx_replay:record"
  @pointer_event Pointer.event()
  @state_event State.event()
  @viewport_event Browser.viewport_event()
  @session_options [
    :sample_rate,
    :keep,
    :max_events,
    :sanitizer,
    :redact,
    :flush,
    :pointer,
    :state
  ]

  @doc """
  Starts recording on the connected mount, for the sampled share of sessions.

  Takes `:default` or a keyword list of live-session options.
  """
  @spec on_mount(
          :default | keyword(),
          map() | :not_mounted_at_router,
          map(),
          Phoenix.LiveView.Socket.t()
        ) ::
          {:cont, Phoenix.LiveView.Socket.t()}
  def on_mount(:default, params, session, socket), do: on_mount([], params, session, socket)

  def on_mount(opts, params, session, socket) when is_list(opts) do
    Keyword.validate!(opts, @session_options)
    config = Config.load(opts)
    # A visit is sampled as a whole: its recordings draw the same.
    {sample, keep} = Visits.draws(visit(session))

    if connected?(socket) and sampled?(config.sample_rate, sample) and memory?(config.max_memory),
      do: {:cont, start(socket, params, session, config, keep)},
      else: {:cont, socket}
  end

  defp visit(%{@kept => %{"visit" => %{"id" => id}}}) when is_binary(id), do: id
  defp visit(_session), do: nil

  @doc """
  Decides whether a session is recorded at `rate`, given a uniform `draw`
  in `0.0..1.0`, its visit's (see `PhoenixReplay.Session.Visits`). Rates
  of `0.0` and `1.0` never consult the draw.
  """
  @spec sampled?(float(), float()) :: boolean()
  def sampled?(rate, draw \\ :rand.uniform())
  def sampled?(rate, _draw) when rate >= 1.0, do: true
  def sampled?(rate, _draw) when rate <= 0.0, do: false
  def sampled?(rate, draw), do: draw <= rate

  defp memory?(nil), do: true
  defp memory?(max_memory), do: Buffer.memory() < max_memory

  defp start(socket, params, session, config, draw) do
    sanitizer = config.sanitizer
    # The request context PhoenixReplay.Plug kept is recorded once, in client.
    {kept, session} = Map.pop(session, @kept)

    recording = %Recording{
      id: Recording.generate_id(),
      view: socket.view,
      params: if(is_map(params), do: sanitizer.sanitize_params(params), else: %{}),
      session: sanitizer.sanitize_params(session),
      connected_at: System.system_time(:millisecond),
      client:
        Browser.build(
          get_connect_params(socket),
          get_connect_info(socket, :user_agent),
          kept,
          config.client.media
        ),
      code: Recording.Code.of(socket.view, config.release, Migration.latest(socket.view))
    }

    :ok = Buffer.open(recording, self(), config, draw)
    Monitor.watch(self(), recording.id)

    state = %{
      id: recording.id,
      url?: false,
      layout?: false,
      sanitizer: sanitizer,
      pointer: config.pointer,
      state: config.state
    }

    socket
    |> put_private(@private, state)
    |> push_event(@record_event, %{
      pointer: config.pointer && Pointer.settings(config.pointer),
      state: config.state && State.settings(config.state)
    })
    |> record(:mount, %{assigns: Assigns.view(socket.assigns, sanitizer)})
    |> attach_hook(@private, :handle_event, &handle_event/3)
    |> attach_params_hook(params)
    |> attach_hook(@private, :handle_info, &handle_info/2)
    |> attach_hook(@private, :after_render, &after_render/1)
  end

  # LiveViews rendered with live_render/3 have no params and cannot take a
  # handle_params hook.
  defp attach_params_hook(socket, :not_mounted_at_router), do: socket

  defp attach_params_hook(socket, _params),
    do: attach_hook(socket, @private, :handle_params, &handle_params/3)

  defp handle_event(@pointer_event, params, socket) do
    case socket.private[@private] do
      %{pointer: %{} = pointer} -> Pointer.capture(self(), params, pointer)
      _not_recording -> :ok
    end

    {:halt, socket}
  end

  defp handle_event(@viewport_event, params, socket) do
    :ok = Browser.viewport(params)
    {:halt, socket}
  end

  defp handle_event(@state_event, params, socket) do
    case socket.private[@private] do
      %{state: %{} = state} -> State.capture(self(), params, state)
      _not_recording -> :ok
    end

    {:halt, socket}
  end

  # The app's own events are recorded from LiveView's telemetry, whatever
  # hooks handle them; see PhoenixReplay.Capture.ViewEvents.
  defp handle_event(_name, _params, socket), do: {:cont, socket}

  defp handle_params(params, uri, socket) do
    %{sanitizer: sanitizer} = socket.private[@private]

    socket =
      socket
      |> capture_url(uri)
      |> record(:params, %{params: sanitizer.sanitize_params(params), uri: uri})

    {:cont, socket}
  end

  defp capture_url(%{private: %{@private => %{url?: false} = state}} = socket, uri) do
    :ok = Buffer.put_url(state.id, uri)
    put_private(socket, @private, %{state | url?: true})
  end

  defp capture_url(socket, _uri), do: socket

  defp handle_info(message, socket), do: {:cont, record(socket, :info, %{tag: tag(message)})}

  defp after_render(socket), do: socket |> capture_layout() |> record_render()

  defp record_render(%{assigns: %{__changed__: changed}} = socket) when map_size(changed) > 0 do
    %{sanitizer: sanitizer} = socket.private[@private]

    case socket.assigns |> Map.take(Map.keys(changed)) |> Assigns.view(sanitizer) do
      assigns when map_size(assigns) > 0 -> record(socket, :render, %{assigns: assigns})
      _empty -> socket
    end
  end

  defp record_render(socket), do: socket

  # The layout is settled by the first render: `mount/3` or an `on_mount`
  # hook may have returned one with `layout:`, which LiveView keeps in
  # `:live_layout`, over the one the view's `use` names.
  defp capture_layout(%{private: %{@private => %{layout?: false} = state}} = socket) do
    layout =
      case Map.get(socket.private, :live_layout, socket.view.__live__()[:layout]) do
        {module, template} -> {inspect(module), to_string(template)}
        _none -> false
      end

    :ok = Buffer.put_layout(state.id, layout)
    put_private(socket, @private, %{state | layout?: true})
  end

  defp capture_layout(socket), do: socket

  defp record(socket, type, data) do
    Buffer.record(self(), type, data)
    socket
  end

  defp tag(message) when is_atom(message), do: message
  defp tag(message) when is_tuple(message) and is_atom(elem(message, 0)), do: elem(message, 0)
  defp tag(_message), do: nil
end
