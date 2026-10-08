defmodule Mix.Tasks.PhoenixReplay.Show do
  @shortdoc "Prints a recording's events, or the view at one of them"

  @moduledoc """
  #{@shortdoc}.

      mix phoenix_replay.show RECORDING_ID [--at INDEX] [--limit ITEMS]

  Without `--at`, it prints `PhoenixReplay.Trace.events/1`: every event
  with its index, label, error flag, the interaction it belongs to and its
  data. With `--at`, `PhoenixReplay.Trace.state/2`: the assigns,
  components and client state at that event, and what it changed. The
  index is the player's, as in `/replay/RECORDING_ID?at=INDEX`.

  Everything is printed by default. `--limit` sets `IO.inspect/2`'s
  `:limit`, one budget of items for the whole output, for a first look at
  a long recording. It starts your application and reads storage, so it
  shows saved recordings.
  """

  use Mix.Task

  alias PhoenixReplay.Trace

  @switches [at: :integer, limit: :integer]

  @impl true
  def run(args) do
    {opts, ids} = OptionParser.parse!(args, strict: @switches)

    id =
      case ids do
        [id] -> id
        _other -> Mix.raise("Usage: mix phoenix_replay.show RECORDING_ID [--at INDEX]")
      end

    Mix.Task.run("app.start")

    recording =
      case Trace.fetch(id) do
        {:ok, recording} -> recording
        {:error, :not_found} -> Mix.raise("No recording #{id}")
      end

    limit = Keyword.get(opts, :limit, :infinity)

    case opts[:at] do
      nil -> Trace.events(recording)
      index -> Trace.state(recording, index)
    end
    |> IO.inspect(pretty: true, limit: limit, printable_limit: :infinity)
  end
end
