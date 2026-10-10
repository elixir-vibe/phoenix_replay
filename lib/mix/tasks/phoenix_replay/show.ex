defmodule Mix.Tasks.PhoenixReplay.Show do
  @shortdoc "Prints a recording's or a visit's events, or the view at one of them"

  @moduledoc """
  #{@shortdoc}.

      mix phoenix_replay.show RECORDING_ID [--at INDEX] [--limit ITEMS]
      mix phoenix_replay.show VISIT_ID [--limit ITEMS]

  Without `--at`, it prints `PhoenixReplay.Trace.events/1`: every event
  with its index, label, error flag, the interaction it belongs to and its
  data. With `--at`, `PhoenixReplay.Trace.state/2`: the assigns,
  components and client state at that event, and what it changed. The
  index is the player's, as in `/replay/RECORDING_ID?at=INDEX`.

  Given a visit's id, a summary's `visit`, it prints the events of each of
  the visit's recordings, in the order they started, each under its id and
  URL; see `PhoenixReplay.Trace.visit/2`.

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

    shown =
      case {Trace.fetch(id), opts[:at]} do
        {{:ok, recording}, nil} -> Trace.events(recording)
        {{:ok, recording}, index} -> Trace.state(recording, index)
        {{:error, :not_found}, nil} -> visit(id)
        {{:error, :not_found}, _index} -> Mix.raise("No recording #{id}")
      end

    # Recorded lists of integers are ids and counts, not text.
    IO.inspect(shown,
      pretty: true,
      limit: Keyword.get(opts, :limit, :infinity),
      printable_limit: :infinity,
      charlists: :as_lists
    )
  end

  # The events of each recording of the visit, under its id and URL.
  defp visit(key) do
    case Trace.visit(key) do
      {:ok, recordings} ->
        for recording <- recordings,
            do: %{recording: recording.id, url: recording.url, events: Trace.events(recording)}

      {:error, :not_found} ->
        Mix.raise("No recording or visit #{key}")
    end
  end
end
