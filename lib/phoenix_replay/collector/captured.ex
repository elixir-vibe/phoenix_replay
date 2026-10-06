defmodule PhoenixReplay.Collector.Captured do
  @moduledoc """
  What a `PhoenixReplay.Collector` records for a telemetry event.

    * `:summary` — one line describing the event in the replay
    * `:language` — what the summary is written in, for the player to
      highlight it: `:sql`, or `nil` for plain text
    * `:measurements` — numbers, with times in milliseconds; `:duration`
      is shown next to the event and checked by `keep: [slower_than: ms]`
    * `:metadata` — the metadata worth keeping
    * `:error` — a description of a failure, which makes the session match
      `keep: [errors: true]`
    * `:mark` — whether the event marks a moment in the session, such as
      a signup or a checkout, rather than measuring work: the player
      gives marks a lane of their own, and the recording list finds
      sessions by their names
  """

  @type t :: %__MODULE__{
          summary: String.t() | nil,
          language: :sql | nil,
          measurements: %{atom() => number()},
          metadata: map(),
          error: String.t() | nil,
          mark: boolean()
        }

  defstruct summary: nil,
            language: nil,
            measurements: %{},
            metadata: %{},
            error: nil,
            mark: false
end
