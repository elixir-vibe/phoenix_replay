defmodule PhoenixReplay.Session.Recovery do
  @moduledoc """
  Saves sessions whose node stopped before they ended.

  A session's chunks stay in storage until its finished recording replaces
  them. If the node stops first, they are left behind. When the application
  starts, nothing is recording yet, so every set of chunks this node left
  belongs to such a session: each is saved as a recording ending in an
  `:exit` event that says it was interrupted, which also makes it match
  `keep: [errors: true]` filters and the dashboard's error filter.
  """

  require Logger

  alias PhoenixReplay.{Config, Storage, Telemetry}
  alias PhoenixReplay.Recording.{Event, Timeline}

  @reason "The node stopped before the session ended. The recording ends at its last chunk written to storage."

  @doc "Saves every session this node left in chunks. Returns their ids."
  @spec run(Config.t()) :: [PhoenixReplay.Recording.id()]
  def run(%Config{storage: storage} \\ Config.load()) do
    for id <- Storage.partials(storage), recover(storage, id) == :ok, do: id
  end

  defp recover(storage, id) do
    with {:ok, partial} <- Storage.fetch_partial(storage, id),
         recording = interrupted(partial),
         :ok <- Storage.save(storage, recording) do
      Telemetry.recovered(recording)
    else
      error ->
        Logger.error("PhoenixReplay: could not recover recording #{id}: #{inspect(error)}")
        error
    end
  end

  defp interrupted(recording) do
    exit = %Event{at: Timeline.duration_ms(recording), type: :exit, data: %{reason: @reason}}
    # The exit ends the recording; once per recovered session.
    # credo:disable-for-next-line Credo.Check.Refactor.AppendSingleItem
    %{recording | events: recording.events ++ [exit]}
  end
end
