defmodule PhoenixReplay.Collector.EctoTest do
  use ExUnit.Case, async: true

  alias PhoenixReplay.Collector.Ecto, as: EctoCollector

  @event [:phoenix_replay, :collector, :ecto_test, :repo, :query]

  defmodule Repo do
    use Ecto.Repo, otp_app: :phoenix_replay, adapter: Ecto.Adapters.SQLite3
  end

  defmodule PrefixedRepo do
    use Ecto.Repo, otp_app: :phoenix_replay, adapter: Ecto.Adapters.SQLite3

    @impl true
    def init(_type, config), do: {:ok, Keyword.put(config, :telemetry_prefix, [:db])}
  end

  defp ms(ms), do: System.convert_time_unit(ms, :millisecond, :native)

  defp metadata(result \\ {:ok, %{}}),
    do: %{query: "SELECT 1", source: "users", params: ["secret"], result: result, repo: :repo}

  test "attaches to the query event of the repo's telemetry prefix" do
    assert EctoCollector.events(repo: Repo) == [@event]
    assert EctoCollector.events(repo: PrefixedRepo) == [[:db, :query]]
  end

  test "records the SQL, source and times, leaving parameters out by default" do
    measurements = %{total_time: ms(3), query_time: ms(2), queue_time: ms(1), idle_time: ms(9)}

    assert {:ok,
            %{
              summary: "SELECT 1",
              measurements: %{duration: 3.0, total_time: 3.0, query_time: 2.0, queue_time: 1.0},
              metadata: %{source: "users"} = metadata,
              error: nil
            }} = EctoCollector.capture(@event, measurements, metadata(), repo: Repo)

    refute Map.has_key?(metadata, :params)

    assert {:ok, %{metadata: %{params: ["secret"]}}} =
             EctoCollector.capture(@event, measurements, metadata(),
               repo: Repo,
               params: true
             )
  end

  test "skips fast queries and records failed ones as errors" do
    opts = [repo: Repo, slower_than: 2]

    assert EctoCollector.capture(@event, %{total_time: ms(1)}, metadata(), opts) == :skip

    assert {:ok, %{error: ":timeout"}} =
             EctoCollector.capture(
               @event,
               %{total_time: ms(2)},
               metadata({:error, :timeout}),
               opts
             )
  end
end
