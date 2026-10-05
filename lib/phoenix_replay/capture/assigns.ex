defmodule PhoenixReplay.Capture.Assigns do
  @moduledoc """
  Takes the assigns a recording keeps, before the sanitizer sees them.

  LiveView's own bookkeeping cannot be replayed, whatever the sanitizer
  does: change tracking, uploads and streams, and in a LiveComponent its
  `@myself` and the flash, which the parent view records.
  """

  @view [:__changed__, :uploads, :streams]
  @component [:myself, :flash | @view]

  @doc "The assigns of a LiveView to record, sanitized."
  @spec view(map(), module()) :: map()
  def view(assigns, sanitizer), do: assigns |> Map.drop(@view) |> sanitizer.sanitize_assigns()

  @doc "The assigns of a LiveComponent to record, sanitized."
  @spec component(map(), module()) :: map()
  def component(assigns, sanitizer),
    do: assigns |> Map.drop(@component) |> sanitizer.sanitize_assigns()
end
