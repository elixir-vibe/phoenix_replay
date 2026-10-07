defmodule PhoenixReplay.Capture.ViewEvents do
  @moduledoc """
  Records the events a LiveView handles, from LiveView's telemetry.

  LiveView emits `[:phoenix, :live_view, :handle_event, :start]` around
  the whole of an event, its `on_mount` hooks included, with the socket
  and params. Recording from it rather than from a hook of the recorder's
  means an app hook that handles an event and halts, wherever it sits in
  `on_mount`, still has its event recorded.

  The handler runs in the LiveView process and finds its session in
  `PhoenixReplay.Session.Buffer`, so a LiveView that is not recorded costs
  one ETS lookup per event. It records `:event`, `%{name: String.t(),
  params: map}`, with the params through the session's
  `PhoenixReplay.Sanitizer`, and the viewport they carry as a `:viewport`
  event; see `PhoenixReplay.Capture.Browser.observe/1`. The events the
  recorder's own script sends, the pointer, state and viewport, are
  recorded by `PhoenixReplay.Recorder` instead.

  Like the other handlers, it reports a failure with
  `[:phoenix_replay, :collector, :exception]` rather than raise, which
  would detach it for the whole application.
  """

  alias PhoenixReplay.Telemetry
  alias PhoenixReplay.Capture.{Browser, Pointer, State}
  alias PhoenixReplay.Session.Buffer

  @handler __MODULE__
  @event [:phoenix, :live_view, :handle_event, :start]

  # Sent by the recorder's script, and recorded by the recorder.
  @own [Pointer.event(), State.event(), Browser.viewport_event()]

  @doc "Attaches the telemetry handler. Called by `PhoenixReplay.Capture.Handlers`."
  @spec attach() :: :ok | {:error, :already_exists}
  def attach, do: :telemetry.attach(@handler, @event, &__MODULE__.handle_event/4, nil)

  @doc "Detaches the telemetry handler, if attached."
  @spec detach() :: :ok
  def detach do
    _result = :telemetry.detach(@handler)
    :ok
  end

  @doc """
  Records a LiveView's event in its process. A failure, such as a custom
  sanitizer raising, is reported with
  `PhoenixReplay.Telemetry.collector_failed/5` instead of raised.
  """
  @spec handle_event([atom()], map(), map(), term()) :: :ok
  def handle_event(event, _measures, metadata, _handler_config) do
    capture(metadata)
    :ok
  catch
    kind, reason -> Telemetry.collector_failed(__MODULE__, event, kind, reason, __STACKTRACE__)
  end

  defp capture(%{event: name, params: params})
       when is_binary(name) and name not in @own and is_map(params) do
    case Buffer.session(self()) do
      {:ok, _id, sanitizer} ->
        params = sanitizer.sanitize_params(Browser.observe(params))
        Buffer.record(self(), :event, %{name: name, params: params})

      :error ->
        :ok
    end
  end

  defp capture(_metadata), do: :ok
end
