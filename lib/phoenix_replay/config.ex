defmodule PhoenixReplay.Config do
  @moduledoc """
  Validated runtime configuration.

  This is the only module that reads the `:phoenix_replay` application
  environment. Everything else receives a `t:t/0` explicitly, which keeps
  configuration decisions at the boundary and lets tests pass their own.

  ## Options

    * `:storage` — `{module, opts}` implementing `PhoenixReplay.Storage`.
      Defaults to `{PhoenixReplay.Storage.File, []}`.
    * `:sanitizer` — module implementing `PhoenixReplay.Sanitizer`.
      Defaults to `PhoenixReplay.Sanitizer.Default`.
    * `:max_events` — events recorded per session before recording stops.
      Defaults to `10_000`.
    * `:sample_rate` — share of sessions to record, from `0.0` to `1.0`.
      Defaults to `1.0`, recording every session. `0.0` turns recording off.
    * `:keep` — keyword list choosing which recorded sessions are saved
      when they end, as described in "Tail sampling" below:
      * `:rate` — share of interactive sessions to save (default `1.0`)
      * `:errors` — always save sessions with an error (default `false`)
      * `:slower_than` — always save sessions with a collected event
        lasting at least this many milliseconds (default `nil`)
    * `:collect` — telemetry events to record alongside LiveView events.
      Each entry is a `PhoenixReplay.Collector` module, `{module, opts}`,
      an event name, or `{event_name, opts}` for
      `PhoenixReplay.Collector.Telemetry`. Every entry accepts `:limit`,
      the events recorded per session (default `1_000`). Defaults to `[]`.
    * `:logs` — keyword list enabling `Logger` collection, or `nil` (the
      default) to leave logs out. See `PhoenixReplay.Recorder.Logs`.
    * `:redact` — a `PhoenixReplay.Redactor` that masks sensitive values
      when a recording is saved: a list of regexes, or regex sources as
      strings, for `PhoenixReplay.Redactor.Patterns`, or `{module, opts}`.
      Defaults to `[]`, which stores recordings as the sanitizer left them.
    * `:flush` — keyword list controlling how running sessions are written
      to storage in chunks, when the storage supports it (see
      `PhoenixReplay.Storage`), or `false` to save each session only when
      it ends:
      * `:events` — events buffered before a chunk is written (default `200`)
      * `:interval` — milliseconds after which buffered events are written
        anyway (default `5_000`)
    * `:max_memory` — bytes of buffered recordings above which new
      sessions are not recorded, or `nil` (the default) for no limit.
    * `:retention` — keyword list controlling `PhoenixReplay.Retention`:
      * `:max_age` — milliseconds after which recordings are deleted
      * `:max_count` — number of most recent recordings to keep
      * `:interval` — milliseconds between pruning runs (default `60_000`)
    * `:persist` — keyword list controlling `PhoenixReplay.Recorder.Persister`:
      * `:attempts` — save attempts before giving up (default `3`)
      * `:backoff` — base delay in milliseconds, multiplied by the attempt
        number (default `1_000`)

  ## Tail sampling

  `:sample_rate` decides when a session mounts whether it is recorded.
  `:keep` decides when it ends whether it is saved: a session with an
  error or a slow event matching `:errors` or `:slower_than` is always
  saved, a session without user interaction is discarded, and `:rate` of
  the rest are saved.

  To save every failing session but only a few others, record every session
  and keep a share of them:

      config :phoenix_replay,
        sample_rate: 1.0,
        keep: [rate: 0.05, errors: true, slower_than: 1_000],
        max_memory: 256 * 1024 * 1024

  Every session is then buffered until it ends, so set `:max_memory`.
  """

  @type retention :: %{
          max_age: pos_integer() | nil,
          max_count: non_neg_integer() | nil,
          interval: pos_integer()
        }

  @type persist :: %{attempts: pos_integer(), backoff: non_neg_integer()}

  @type keep :: %{rate: float(), errors: boolean(), slower_than: pos_integer() | nil}

  @typedoc "A `PhoenixReplay.Collector` and its options."
  @type collector :: {module(), keyword()}

  @typedoc "A `PhoenixReplay.Redactor` module and its options."
  @type redactor :: {module(), keyword()}

  @type flush :: %{events: pos_integer(), interval: pos_integer()}

  @type logs :: %{level: Logger.level(), metadata: [atom()], limit: pos_integer()}

  @typedoc "A storage backend module and its options."
  @type storage :: {module(), keyword()}

  @type t :: %__MODULE__{
          storage: storage(),
          sanitizer: module(),
          max_events: pos_integer(),
          sample_rate: float(),
          keep: keep(),
          collect: [collector()],
          logs: logs() | nil,
          redact: redactor() | nil,
          max_memory: pos_integer() | nil,
          flush: flush() | nil,
          retention: retention(),
          persist: persist()
        }

  defstruct storage: {PhoenixReplay.Storage.File, []},
            sanitizer: PhoenixReplay.Sanitizer.Default,
            max_events: 10_000,
            sample_rate: 1.0,
            keep: %{rate: 1.0, errors: false, slower_than: nil},
            collect: [],
            logs: nil,
            redact: nil,
            max_memory: nil,
            flush: %{events: 200, interval: 5_000},
            retention: %{max_age: nil, max_count: nil, interval: 60_000},
            persist: %{attempts: 3, backoff: 1_000}

  @doc """
  Loads and validates configuration from the application environment.

  `overrides` take precedence over the environment. Module-keyed entries,
  such as an endpoint configured with `otp_app: :phoenix_replay`, belong to
  those modules and are skipped.
  """
  @spec load(keyword()) :: t()
  def load(overrides \\ []) when is_list(overrides) do
    :phoenix_replay
    |> Application.get_all_env()
    |> Enum.reject(fn {key, _value} -> module_key?(key) end)
    |> Kernel.++(overrides)
    |> new()
  end

  @doc """
  Builds a configuration from a keyword list.

  Raises `ArgumentError` for unknown keys or invalid values.
  """
  @spec new(keyword()) :: t()
  def new(opts) when is_list(opts) do
    Enum.reduce(opts, %__MODULE__{}, &put/2)
  end

  defp module_key?(key), do: match?("Elixir." <> _rest, Atom.to_string(key))

  defp put({:storage, {module, opts}}, config) when is_atom(module) and is_list(opts),
    do: %{config | storage: {module, opts}}

  defp put({:storage, module}, config) when is_atom(module),
    do: %{config | storage: {module, []}}

  defp put({:sanitizer, module}, config) when is_atom(module),
    do: %{config | sanitizer: module}

  defp put({:max_events, max}, config) when is_integer(max) and max > 0,
    do: %{config | max_events: max}

  defp put({:sample_rate, rate}, config) when is_number(rate) and rate >= 0 and rate <= 1,
    do: %{config | sample_rate: rate / 1}

  defp put({:keep, opts}, config) when is_list(opts),
    do: %{
      config
      | keep: merge(config.keep, opts, &valid_keep?/2) |> Map.update!(:rate, &(&1 / 1))
    }

  defp put({:collect, entries}, config) when is_list(entries),
    do: %{config | collect: Enum.map(entries, &collector/1)}

  defp put({:logs, nil}, config), do: %{config | logs: nil}

  defp put({:logs, opts}, config) when is_list(opts),
    do: %{config | logs: merge(%{level: :info, metadata: [], limit: 1_000}, opts, &valid_logs?/2)}

  defp put({:redact, []}, config), do: %{config | redact: nil}

  defp put({:redact, patterns}, config) when is_list(patterns),
    do: %{
      config
      | redact: {PhoenixReplay.Redactor.Patterns, patterns: Enum.map(patterns, &pattern/1)}
    }

  defp put({:redact, {module, opts}}, config) when is_atom(module) and is_list(opts),
    do: %{config | redact: {module, opts}}

  defp put({:redact, module}, config) when is_atom(module) and not is_nil(module),
    do: %{config | redact: {module, []}}

  defp put({:max_memory, max}, config) when is_nil(max) or (is_integer(max) and max > 0),
    do: %{config | max_memory: max}

  defp put({:flush, false}, config), do: %{config | flush: nil}

  defp put({:flush, opts}, config) when is_list(opts),
    do: %{config | flush: merge(%{events: 200, interval: 5_000}, opts, &valid_flush?/2)}

  defp put({:retention, opts}, config) when is_list(opts),
    do: %{config | retention: merge(config.retention, opts, &valid_retention?/2)}

  defp put({:persist, opts}, config) when is_list(opts),
    do: %{config | persist: merge(config.persist, opts, &valid_persist?/2)}

  defp put({key, value}, _config) do
    raise ArgumentError,
          "invalid :phoenix_replay configuration #{inspect(key)}: #{inspect(value)}"
  end

  defp merge(defaults, opts, valid?) do
    Enum.reduce(opts, defaults, fn {key, value}, acc ->
      if Map.has_key?(acc, key) and valid?.(key, value) do
        Map.put(acc, key, value)
      else
        raise ArgumentError,
              "invalid :phoenix_replay configuration #{inspect(key)}: #{inspect(value)}"
      end
    end)
  end

  defp collector([name | _rest] = event) when is_atom(name),
    do: {PhoenixReplay.Collector.Telemetry, [event: event]}

  defp collector({[name | _rest] = event, opts}) when is_atom(name) and is_list(opts),
    do: {PhoenixReplay.Collector.Telemetry, [{:event, event} | opts]}

  defp collector({module, opts}) when is_atom(module) and is_list(opts), do: {module, opts}
  defp collector(module) when is_atom(module), do: {module, []}

  defp collector(entry),
    do: raise(ArgumentError, "invalid :phoenix_replay :collect entry: #{inspect(entry)}")

  defp pattern(%Regex{} = regex), do: regex
  defp pattern(source) when is_binary(source), do: Regex.compile!(source)

  defp pattern(pattern),
    do: raise(ArgumentError, "invalid :phoenix_replay :redact pattern: #{inspect(pattern)}")

  defp valid_keep?(:rate, value), do: is_number(value) and value >= 0 and value <= 1
  defp valid_keep?(:errors, value), do: is_boolean(value)
  defp valid_keep?(:slower_than, value), do: is_nil(value) or pos_integer?(value)

  defp valid_logs?(:level, value), do: value in Logger.levels()
  defp valid_logs?(:metadata, value), do: is_list(value) and Enum.all?(value, &is_atom/1)
  defp valid_logs?(:limit, value), do: pos_integer?(value)

  defp valid_flush?(_key, value), do: pos_integer?(value)

  defp valid_retention?(:max_age, value), do: is_nil(value) or pos_integer?(value)
  defp valid_retention?(:max_count, value), do: is_nil(value) or non_neg_integer?(value)
  defp valid_retention?(:interval, value), do: pos_integer?(value)

  defp valid_persist?(:attempts, value), do: pos_integer?(value)
  defp valid_persist?(:backoff, value), do: non_neg_integer?(value)

  defp pos_integer?(value), do: is_integer(value) and value > 0
  defp non_neg_integer?(value), do: is_integer(value) and value >= 0
end
