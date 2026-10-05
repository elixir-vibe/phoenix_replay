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
  """

  @type t :: %__MODULE__{
          summary: String.t() | nil,
          language: :sql | nil,
          measurements: %{atom() => number()},
          metadata: map(),
          error: String.t() | nil
        }

  defstruct summary: nil, language: nil, measurements: %{}, metadata: %{}, error: nil
end
