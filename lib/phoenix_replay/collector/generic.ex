defmodule PhoenixReplay.Collector.Generic do
  @moduledoc """
  Collects any telemetry event.

  This is the collector behind a bare event name in `:collect`:

      config :phoenix_replay,
        collect: [
          [:my_app, :checkout, :stop],
          {[:my_app, :search, :stop],
           metadata: [:query], keep: &(&1.results > 0), summary: &"search \#{&1.query}"}
        ]

  ## Options

    * `:event` — the event name (required)
    * `:metadata` — metadata keys to keep. Defaults to `[]`, keeping none,
      because metadata often holds whole sockets and structs.
    * `:keep` — a function of the metadata returning whether to record the
      event, as in `Telemetry.Metrics`
    * `:summary` — a function of the metadata returning the line shown in
      the replay. Defaults to the event name.
    * `:mark` — `true` for an event that marks a moment, such as a signup
      or a completed checkout, as an analytics event would, or the mark's
      name, such as `"Checkout completed"`; see
      `PhoenixReplay.Collector.Captured`. Defaults to `false`.

  Measurements are kept, with times converted to milliseconds by
  `PhoenixReplay.Collector.milliseconds/1`. An event whose name ends in
  `:exception` is recorded as an error, described by its `kind` and
  `reason` metadata.
  """

  @behaviour PhoenixReplay.Collector

  alias PhoenixReplay.Collector
  alias PhoenixReplay.Collector.Captured

  @impl true
  def events(opts), do: [Keyword.fetch!(opts, :event)]

  @impl true
  def capture(event, measurements, metadata, opts) do
    if keep?(opts[:keep], metadata) do
      {:ok,
       %Captured{
         summary: summary(opts[:summary], event, metadata),
         measurements: Collector.milliseconds(measurements),
         metadata: Map.take(metadata, Keyword.get(opts, :metadata, [])),
         error: error(event, metadata),
         mark: Keyword.get(opts, :mark, false)
       }}
    else
      :skip
    end
  end

  defp keep?(nil, _metadata), do: true
  defp keep?(keep, metadata) when is_function(keep, 1), do: keep.(metadata)

  defp summary(nil, event, _metadata), do: Collector.name(event)
  defp summary(summary, _event, metadata) when is_function(summary, 1), do: summary.(metadata)

  defp error(event, %{kind: kind, reason: reason}) do
    if exception?(event), do: Collector.error(kind, reason)
  end

  defp error(_event, _metadata), do: nil

  defp exception?([:exception]), do: true
  defp exception?([_name | rest]), do: exception?(rest)
  defp exception?([]), do: false
end
