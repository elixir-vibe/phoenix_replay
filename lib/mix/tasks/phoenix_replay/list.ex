defmodule Mix.Tasks.PhoenixReplay.List do
  @shortdoc "Lists recordings"

  @moduledoc """
  #{@shortdoc}, most recent first, as `PhoenixReplay.Trace.find/2` returns
  them.

      mix phoenix_replay.list [--errors] [--view MyAppWeb.CheckoutLive]
        [--event save] [--mark my_app.checkout.completed] [--text checkout]
        [--source google] [--medium cpc] [--campaign spring]
        [--device-type phone|tablet|desktop] [--browser "Mobile Safari"]
        [--within 1h|24h|7d] [--longer-than 60] [--limit 20]

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
    text: :string,
    within: :string,
    limit: :integer
  ]

  @impl true
  def run(args) do
    {opts, _rest} = OptionParser.parse!(args, strict: @switches)
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
end
