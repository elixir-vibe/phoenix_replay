defmodule PhoenixReplay.Collector do
  @moduledoc """
  Behaviour for recording `:telemetry` events alongside LiveView events.

  A collector names the events it listens to and turns each one into a
  `PhoenixReplay.Collector.Captured` struct, or skips it. Collectors are configured under
  `:collect`:

      config :phoenix_replay,
        collect: [
          {PhoenixReplay.Collector.Ecto, repo: MyApp.Repo, slower_than: 5},
          PhoenixReplay.Collector.Finch,
          {[:my_app, :checkout, :stop], metadata: [:order_id]}
        ]

  A bare event name, or `{event_name, opts}`, is shorthand for
  `PhoenixReplay.Collector.Generic`.

  `PhoenixReplay.Capture.Collectors` attaches every collector when the
  application starts and records what it captures in the session of the
  process that emitted the event, or of the process that started it
  through `Task` (its `$callers`). Events from processes that belong to no
  recorded session cost one ETS lookup per caller. Captured data then goes
  through the session's `PhoenixReplay.Sanitizer` and `:redact` patterns,
  and at most `:limit` events per collector are recorded for each session.

  `capture/4` runs in the process that emitted the event, so it should be
  cheap. Keep only the metadata a reader of the replay needs: metadata
  often holds whole sockets, connections and structs.

  ## Example

      defmodule MyApp.PaymentCollector do
        @behaviour PhoenixReplay.Collector

        alias PhoenixReplay.Collector
        alias PhoenixReplay.Collector.Captured

        @impl true
        def events(_opts), do: [[:my_app, :payment, :stop]]

        @impl true
        def capture(_event, measurements, metadata, _opts) do
          {:ok,
           %Captured{
             summary: "charge \#{metadata.amount} \#{metadata.currency}",
             measurements: Collector.milliseconds(measurements),
             metadata: Map.take(metadata, [:provider])
           }}
        end
      end
  """

  alias PhoenixReplay.Collector.Captured

  @doc "The telemetry events to attach to."
  @callback events(opts :: keyword()) :: [:telemetry.event_name()]

  @doc "Captures an event, or skips it."
  @callback capture(
              event :: :telemetry.event_name(),
              measurements :: map(),
              metadata :: map(),
              opts :: keyword()
            ) :: {:ok, Captured.t()} | :skip

  @time_suffix "_time"
  @dropped [:monotonic_time, :system_time]

  @doc """
  Converts time measurements from native units to milliseconds.

  `:duration` and keys ending in `_time` are converted, following the
  conventions of `:telemetry.span/3`, Phoenix and Ecto. `:monotonic_time`
  and `:system_time` are timestamps rather than durations and are dropped.
  Other numbers are kept as they are.
  """
  @spec milliseconds(map()) :: %{atom() => number()}
  def milliseconds(measurements) when is_map(measurements) do
    for {key, value} <- measurements, is_number(value), key not in @dropped, into: %{} do
      if time?(key), do: {key, to_milliseconds(value)}, else: {key, value}
    end
  end

  @doc "Converts a native time unit integer to milliseconds, rounded to microseconds."
  @spec to_milliseconds(number()) :: number()
  def to_milliseconds(native) when is_integer(native),
    do: System.convert_time_unit(native, :native, :microsecond) / 1_000

  def to_milliseconds(value), do: value

  @doc "Joins an event name with dots, as in `\"my_app.repo.query\"`."
  @spec name(:telemetry.event_name()) :: String.t()
  def name(event), do: Enum.map_join(event, ".", &Atom.to_string/1)

  @doc "Describes an `:exception` event's `kind` and `reason` in one line."
  @spec error(atom(), term()) :: String.t()
  def error(kind, reason), do: kind |> Exception.format_banner(reason) |> first_line()

  @doc "Describes the error in an `{:error, reason}` result, or returns `nil` for other results."
  @spec result_error(term()) :: String.t() | nil
  def result_error({:error, %{__exception__: true} = exception}), do: Exception.message(exception)
  def result_error({:error, reason}), do: inspect(reason)
  def result_error(_result), do: nil

  defp time?(:duration), do: true

  defp time?(key) when is_atom(key),
    do: key |> Atom.to_string() |> String.ends_with?(@time_suffix)

  defp time?(_key), do: false

  defp first_line(text), do: text |> String.split("\n", parts: 2) |> hd()
end
