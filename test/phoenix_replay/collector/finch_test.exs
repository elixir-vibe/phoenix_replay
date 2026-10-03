defmodule PhoenixReplay.Collector.FinchTest do
  use ExUnit.Case, async: true

  alias PhoenixReplay.Collector.Finch, as: FinchCollector

  @event [:finch, :request, :stop]
  @request %{
    method: "GET",
    scheme: :https,
    host: "api.example.com",
    port: 443,
    path: "/v1/charges",
    query: "token=abc"
  }

  defp duration(ms), do: %{duration: System.convert_time_unit(ms, :millisecond, :native)}

  test "records the request without its query string, and the status" do
    assert {:ok,
            %{
              summary: "GET https://api.example.com/v1/charges",
              measurements: %{duration: 4.0},
              metadata: %{status: 402},
              error: nil
            }} =
             FinchCollector.capture(
               @event,
               duration(4),
               %{request: @request, result: {:ok, %{status: 402}}},
               []
             )

    metadata = %{request: @request, result: {:ok, %{status: 200}}}

    assert {:ok, %{summary: "GET https://api.example.com/v1/charges?token=abc"}} =
             FinchCollector.capture(@event, duration(4), metadata, query: true)
  end

  test "records failed requests as errors and skips fast ones" do
    assert {:ok, %{metadata: %{}, error: ":closed"}} =
             FinchCollector.capture(
               @event,
               duration(4),
               %{request: @request, result: {:error, :closed}},
               []
             )

    assert FinchCollector.capture(@event, duration(1), %{request: @request}, slower_than: 2) ==
             :skip
  end
end
