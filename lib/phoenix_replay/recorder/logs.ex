defmodule PhoenixReplay.Recorder.Logs do
  @moduledoc """
  Records log messages in the session of the process that logged them.

      config :phoenix_replay, logs: [level: :info, metadata: [:request_id]]

  ## Options

    * `:level` — the lowest level recorded. Defaults to `:info`. Messages
      below the `:logger` primary level are never emitted at all.
    * `:metadata` — Logger metadata keys to keep. Defaults to `[]`.
    * `:limit` — log messages recorded per session. Defaults to `1_000`.

  This is a `:logger` handler. `:logger` calls handlers in the process that
  logs, so a message belongs to the session of that process, or of the
  first of its `$callers` that has one, as for
  `PhoenixReplay.Recorder.Collectors`. Messages are formatted on one line,
  their metadata goes through the session's `PhoenixReplay.Sanitizer`, and
  their text through the `:redact` patterns. Each is recorded as a `:log`
  event.

  `:logger` removes a handler that raises, so failures are reported with
  `[:phoenix_replay, :collector, :exception]` instead.
  """

  alias PhoenixReplay.{Config, Sanitizer, Telemetry}
  alias PhoenixReplay.Recorder.{Buffer, Collectors}

  @formatter %{template: [:msg], single_line: true}

  @doc """
  Adds the `:logger` handler when `:logs` is configured. Called by
  `PhoenixReplay.Recorder.Handlers`.
  """
  @spec attach(Config.t(), atom()) :: :ok | {:error, term()}
  def attach(config, id \\ __MODULE__)
  def attach(%Config{logs: nil}, _id), do: :ok

  def attach(%Config{logs: logs}, id),
    do: :logger.add_handler(id, __MODULE__, %{level: logs.level, config: logs})

  @doc "Removes the `:logger` handler, if added."
  @spec detach(atom()) :: :ok
  def detach(id \\ __MODULE__) do
    _result = :logger.remove_handler(id)
    :ok
  end

  @doc false
  @spec log(:logger.log_event(), :logger.handler_config()) :: :ok
  def log(%{level: level, meta: meta} = event, %{config: logs}) do
    case Buffer.attribute([self() | Collectors.callers()]) do
      {:ok, session, config} ->
        data = %{
          level: level,
          message: message(event),
          metadata: config.sanitizer.sanitize_params(Map.take(meta, logs.metadata))
        }

        Buffer.collect(session, :log, Sanitizer.redact(data, config.redact), "log", logs.limit)

      :error ->
        :ok
    end

    :ok
  catch
    kind, reason -> Telemetry.collector_failed(__MODULE__, [:log], kind, reason, __STACKTRACE__)
  end

  defp message(event) do
    event |> :logger_formatter.format(@formatter) |> IO.chardata_to_string()
  end
end
