defmodule PhoenixReplay.Collector.Ecto do
  @moduledoc """
  Collects Ecto queries.

      config :phoenix_replay,
        collect: [{PhoenixReplay.Collector.Ecto, repo: MyApp.Repo, slower_than: 2}]

  Ecto emits its query event in the process that runs the query, so
  queries from a LiveView and from its `start_async/3` and `assign_async/3`
  tasks are recorded in its session. Each query records its SQL as the
  summary, its `source`, and its total, query, queue and decode times in
  milliseconds. A query that returned an error is recorded as an error.

  ## Options

    * `:repo` — the repo whose queries to collect (required). Add one entry
      per repo. Its `:telemetry_prefix` is read from `c:Ecto.Repo.config/0`.
    * `:slower_than` — milliseconds below which queries are skipped
    * `:params` — whether to record query parameters, which may hold
      personal data. Defaults to `false`.
  """

  @behaviour PhoenixReplay.Collector

  alias PhoenixReplay.Collector
  alias PhoenixReplay.Collector.Captured

  @times [:total_time, :query_time, :queue_time, :decode_time]

  @impl true
  def events(opts) do
    repo = Keyword.fetch!(opts, :repo)
    prefix = Keyword.fetch!(repo.config(), :telemetry_prefix)
    # Telemetry names the event after the repo's prefix; once, at attach time.
    # credo:disable-for-next-line Credo.Check.Refactor.AppendSingleItem
    [prefix ++ [:query]]
  end

  @impl true
  def capture(_event, measurements, metadata, opts) do
    measurements = measurements |> Map.take(@times) |> Collector.milliseconds()
    duration = Map.get(measurements, :total_time, 0)

    if duration >= Keyword.get(opts, :slower_than, 0) do
      {:ok,
       %Captured{
         summary: metadata[:query],
         measurements: Map.put(measurements, :duration, duration),
         metadata: metadata(metadata, opts),
         error: Collector.result_error(metadata[:result])
       }}
    else
      :skip
    end
  end

  defp metadata(metadata, opts) do
    keys = if Keyword.get(opts, :params, false), do: [:source, :params], else: [:source]
    Map.take(metadata, keys)
  end
end
