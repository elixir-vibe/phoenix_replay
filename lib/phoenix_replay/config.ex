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
    * `:retention` — keyword list controlling `PhoenixReplay.Retention`:
      * `:max_age` — milliseconds after which recordings are deleted
      * `:max_count` — number of most recent recordings to keep
      * `:interval` — milliseconds between pruning runs (default `60_000`)
    * `:persist` — keyword list controlling `PhoenixReplay.Recorder.Persister`:
      * `:attempts` — save attempts before giving up (default `3`)
      * `:backoff` — base delay in milliseconds, multiplied by the attempt
        number (default `1_000`)
  """

  @type retention :: %{
          max_age: pos_integer() | nil,
          max_count: non_neg_integer() | nil,
          interval: pos_integer()
        }

  @type persist :: %{attempts: pos_integer(), backoff: non_neg_integer()}

  @typedoc "A storage backend module and its options."
  @type storage :: {module(), keyword()}

  @type t :: %__MODULE__{
          storage: storage(),
          sanitizer: module(),
          max_events: pos_integer(),
          retention: retention(),
          persist: persist()
        }

  defstruct storage: {PhoenixReplay.Storage.File, []},
            sanitizer: PhoenixReplay.Sanitizer.Default,
            max_events: 10_000,
            retention: %{max_age: nil, max_count: nil, interval: 60_000},
            persist: %{attempts: 3, backoff: 1_000}

  @doc """
  Loads and validates configuration from the application environment.

  Module-keyed entries, such as an endpoint configured with
  `otp_app: :phoenix_replay`, belong to those modules and are skipped.
  """
  @spec load() :: t()
  def load do
    :phoenix_replay
    |> Application.get_all_env()
    |> Enum.reject(fn {key, _value} -> module_key?(key) end)
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

  defp valid_retention?(:max_age, value), do: is_nil(value) or pos_integer?(value)
  defp valid_retention?(:max_count, value), do: is_nil(value) or non_neg_integer?(value)
  defp valid_retention?(:interval, value), do: pos_integer?(value)

  defp valid_persist?(:attempts, value), do: pos_integer?(value)
  defp valid_persist?(:backoff, value), do: non_neg_integer?(value)

  defp pos_integer?(value), do: is_integer(value) and value > 0
  defp non_neg_integer?(value), do: is_integer(value) and value >= 0
end
