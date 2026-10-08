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

  @doc """
  Writes a recorded value as `Kernel.inspect/2` does with `opts`, but lists
  of integers as lists: recorded params and assigns come from JSON or your
  code, where `[11]` is a list of ids, not the charlist `~c"\\v"`.
  """
  @spec inspect(term(), keyword()) :: String.t()
  def inspect(value, opts \\ []),
    do: Kernel.inspect(value, Keyword.put_new(opts, :charlists, :as_lists))
end
