defmodule PhoenixReplay.Sanitizer do
  @moduledoc """
  Behaviour for removing sensitive or bulky data before it is recorded.

  `sanitize_assigns/1` receives LiveView assigns (atom keys) for the initial
  mount and for each render's changed keys. `sanitize_params/1` receives event
  params, URL params and the session (string keys).

  The default implementation is `PhoenixReplay.Sanitizer.Default`. A custom
  sanitizer can delegate to it for the parts it does not change:

      defmodule MyApp.ReplaySanitizer do
        @behaviour PhoenixReplay.Sanitizer

        @impl true
        def sanitize_assigns(assigns) do
          assigns
          |> Map.drop([:current_user])
          |> PhoenixReplay.Sanitizer.Default.sanitize_assigns()
        end

        @impl true
        defdelegate sanitize_params(params), to: PhoenixReplay.Sanitizer.Default
      end

      config :phoenix_replay, sanitizer: MyApp.ReplaySanitizer

  Collected telemetry metadata and log metadata go through
  `sanitize_params/1` too. Free text such as SQL, log messages and exit
  reasons has no keys to filter, so it goes through `redact/2` with the
  `:redact` patterns instead.
  """

  @callback sanitize_assigns(map()) :: map()
  @callback sanitize_params(map()) :: map()

  @redacted "[REDACTED]"

  @doc """
  Replaces every match of `patterns` in the strings within `term` with
  `"[REDACTED]"`, recursing into maps, lists and tuples. Structs are kept
  as they are.
  """
  @spec redact(term(), [Regex.t()]) :: term()
  def redact(term, []), do: term

  def redact(string, patterns) when is_binary(string),
    do: Enum.reduce(patterns, string, &Regex.replace(&1, &2, @redacted))

  def redact(%_{} = struct, _patterns), do: struct

  def redact(map, patterns) when is_map(map),
    do: Map.new(map, fn {k, v} -> {k, redact(v, patterns)} end)

  def redact(list, patterns) when is_list(list), do: Enum.map(list, &redact(&1, patterns))

  def redact(tuple, patterns) when is_tuple(tuple),
    do: tuple |> Tuple.to_list() |> redact(patterns) |> List.to_tuple()

  def redact(term, _patterns), do: term
end
