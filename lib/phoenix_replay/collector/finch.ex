defmodule PhoenixReplay.Collector.Finch do
  @moduledoc """
  Collects HTTP requests made with Finch, and so with Req.

      config :phoenix_replay, collect: [PhoenixReplay.Collector.Finch]

  Each request records `METHOD scheme://host/path` as the summary, the
  response status, and the duration in milliseconds. Query strings are
  left out, because they often carry tokens. A request that failed is
  recorded as an error; a response status is not, since many applications
  expect some error statuses.

  ## Options

    * `:slower_than` — milliseconds below which requests are skipped
    * `:query` — whether to record query strings. Defaults to `false`.
  """

  @behaviour PhoenixReplay.Collector

  alias PhoenixReplay.Collector
  alias PhoenixReplay.Collector.Captured

  @impl true
  def events(_opts), do: [[:finch, :request, :stop]]

  @impl true
  def capture(_event, measurements, %{request: request} = metadata, opts) do
    measurements = Collector.milliseconds(measurements)

    if Map.get(measurements, :duration, 0) >= Keyword.get(opts, :slower_than, 0) do
      {:ok,
       %Captured{
         summary: summary(request, Keyword.get(opts, :query, false)),
         measurements: measurements,
         metadata: status(metadata[:result]),
         error: Collector.result_error(metadata[:result])
       }}
    else
      :skip
    end
  end

  def capture(_event, _measurements, _metadata, _opts), do: :skip

  defp summary(request, query?) do
    url =
      %URI{
        scheme: to_string(request.scheme),
        host: request.host,
        port: request.port,
        path: request.path,
        query: if(query?, do: request.query)
      }
      |> URI.to_string()

    "#{request.method} #{url}"
  end

  defp status({:ok, %{status: status}}), do: %{status: status}
  defp status(_result), do: %{}
end
