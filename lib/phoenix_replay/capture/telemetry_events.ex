defmodule PhoenixReplay.Capture.TelemetryEvents do
  @moduledoc """
  Records telemetry events captured by the configured `PhoenixReplay.Collector`s.

  Each collector is attached once, when the application starts. Its handler
  runs in the process that emitted the event and handles it in a fixed
  order:

    1. Finds the session of the emitting process, or of the first of its
       `$callers` that has one, so `start_async/3`, `assign_async/3` and
       `Task` work belongs to the LiveView that started it. Events no
       session claims stop here, at the cost of one ETS lookup per process.
    2. Lets the collector capture or skip the event.
    3. Passes captured metadata through the session's
       `PhoenixReplay.Sanitizer`. Text such as SQL is masked later, when
       the recording is saved, by the session's `PhoenixReplay.Redactor`.
    4. Records a `:telemetry` event, unless the collector reached its
       `:limit` for the session, in which case the event is counted as
       dropped.

  `:telemetry` permanently detaches a handler that raises, so a collector
  that raises is reported with `[:phoenix_replay, :collector, :exception]`
  instead; see `PhoenixReplay.Telemetry`.
  """

  alias PhoenixReplay.{Collector, Config, Telemetry}
  alias PhoenixReplay.Collector.Captured
  alias PhoenixReplay.Session.Buffer

  @default_limit 1_000

  @doc """
  Attaches the configured collectors. Called by `PhoenixReplay.Capture.Handlers`.

  Handlers are identified by `{prefix, index}`.
  """
  @spec attach(Config.t(), term()) :: :ok
  def attach(%Config{collect: collectors}, prefix \\ __MODULE__) do
    collectors
    |> Enum.with_index()
    |> Enum.each(fn {{module, opts}, index} ->
      {limit, opts} = Keyword.pop(opts, :limit, @default_limit)

      :ok =
        :telemetry.attach_many(
          {prefix, index},
          module.events(opts),
          &__MODULE__.handle_event/4,
          {module, opts, limit}
        )
    end)
  end

  @doc "Detaches the collectors attached with `prefix`."
  @spec detach(term()) :: :ok
  def detach(prefix \\ __MODULE__) do
    for %{id: {^prefix, _index} = id} <- :telemetry.list_handlers([]), do: :telemetry.detach(id)
    :ok
  end

  @doc "Handles a telemetry event for a collector."
  @spec handle_event([atom()], map(), map(), {module(), keyword(), pos_integer()}) :: :ok
  def handle_event(event, measurements, metadata, {module, opts, limit}) do
    with {:ok, session, sanitizer} <- Buffer.attribute([self() | callers()]),
         {:ok, %Captured{} = captured} <- module.capture(event, measurements, metadata, opts) do
      data = %{
        event: event,
        summary: captured.summary,
        measurements: captured.measurements,
        metadata: sanitizer.sanitize_params(captured.metadata),
        error: captured.error
      }

      Buffer.collect(session, :telemetry, data, Collector.name(event), limit)
    end

    :ok
  catch
    kind, reason -> Telemetry.collector_failed(module, event, kind, reason, __STACKTRACE__)
  end

  @doc "The `$callers` of the current process, which `Task` sets."
  @spec callers() :: [pid()]
  def callers do
    case Process.get(:"$callers") do
      callers when is_list(callers) -> callers
      _none -> []
    end
  end
end
