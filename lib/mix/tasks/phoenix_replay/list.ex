defmodule Mix.Tasks.PhoenixReplay.List do
  @shortdoc "Lists recordings"

  @moduledoc """
  #{@shortdoc}, most recent first, as `PhoenixReplay.Trace.find/2` returns
  them.

      mix phoenix_replay.list [--errors] [--view MyAppWeb.CheckoutLive]
        [--event save] [--mark my_app.checkout.completed] [--text checkout]
        [--source google] [--medium cpc] [--campaign spring]
        [--device-type phone|tablet|desktop] [--browser "Mobile Safari"]
        [--within 15m|1h|24h|7d|30d] [--from 2026-10-06T14:00:00Z]
        [--to 2026-10-06T15:00:00Z] [--longer-than 60] [--limit 20]

  It starts your application and reads storage, so it lists saved
  recordings: sessions still running are in the server's memory; call
  `PhoenixReplay.Trace.find/2` in the server to see them.
  """

  use Mix.Task

  alias PhoenixReplay.Trace

  @switches [
    errors: :boolean,
    view: :string,
    event: :string,
    mark: :string,
    source: :string,
    medium: :string,
    campaign: :string,
    device_type: :string,
    browser: :string,
    longer_than: :integer,
    from: :string,
    to: :string,
    text: :string,
    within: :string,
    limit: :integer
  ]

  @impl true
  def run(args) do
    {opts, _rest} = OptionParser.parse!(args, strict: @switches)
    opts = opts |> times(:from) |> times(:to)
    Mix.Task.run("app.start")

    try do
      opts
      |> Keyword.put(:live, false)
      |> Trace.find()
      |> IO.inspect(pretty: true, limit: :infinity)
    rescue
      error in ArgumentError -> Mix.raise(Exception.message(error))
    end
  end

  # An ISO 8601 time on the command line, for `PhoenixReplay.Trace.find/2`.
  defp times(opts, key) do
    case Keyword.fetch(opts, key) do
      {:ok, text} ->
        case DateTime.from_iso8601(text) do
          {:ok, time, _offset} -> Keyword.put(opts, key, time)
          {:error, _reason} -> Mix.raise("--#{key} must be an ISO 8601 time, got: #{text}")
        end

      :error ->
        opts
    end
  end
end
