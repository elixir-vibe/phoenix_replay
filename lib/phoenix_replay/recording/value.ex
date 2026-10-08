defmodule PhoenixReplay.Recording.Value do
  @moduledoc """
  Facts about recorded values that sanitizing, redacting and diffing them
  share.
  """

  # Their fields mean nothing apart, as the minute of a timestamp does
  # not, and no key in them tells a secret apart.
  @opaque_structs [
    Date,
    DateTime,
    Decimal,
    MapSet,
    NaiveDateTime,
    Range,
    Regex,
    Time,
    URI,
    Version
  ]

  @doc """
  Standard-library structs taken whole: kept as they are by
  `PhoenixReplay.Sanitizer.Default`, and compared whole when the player
  shows what changed. `PhoenixReplay.Redactor` looks inside `URI`, whose
  path and query hold whatever was typed into them.
  """
  @spec opaque_structs() :: [module()]
  def opaque_structs, do: @opaque_structs
end
