defmodule PhoenixReplay.Replay do
  @moduledoc """
  How your app's recordings are replayed, as a whole. For how one LiveView
  renders in a replay, see `PhoenixReplay.Replay.View`.

  Replays render today's templates and root layout with the assigns
  recorded then, and most need nothing more: an assign a recording lacks
  is rendered as `nil`, and the root layout, rendered again at each moment,
  gives the replayed page's `<html>` and `<body>` their attributes, such
  as a theme. A module of this behaviour, configured as `:replay`, covers
  what that cannot:

      config :phoenix_replay, replay: MyAppWeb.Replay

      defmodule MyAppWeb.Replay do
        @behaviour PhoenixReplay.Replay

        # Recordings made before `:dark_mode` became `:theme`.
        @impl true
        def prepare(_view, %{dark_mode: dark?} = assigns),
          do: Map.put_new(assigns, :theme, if(dark?, do: "dark", else: "light"))

        def prepare(_view, assigns), do: assigns
      end

  Both callbacks are optional.
  """

  @doc """
  The recorded `assigns` of `view` at a moment, as its template renders
  them today: called before each replayed render, to adapt what older
  recordings hold, such as an assign since renamed.
  """
  @callback prepare(view :: module(), assigns :: map()) :: map()

  @doc """
  Attributes for the replayed page's `<html>` at a moment, besides those
  the root layout renders, for a layout whose attributes come from
  something other than its assigns.
  """
  @callback root_attributes(view :: module(), assigns :: map()) :: %{
              optional(String.t() | atom()) => String.t() | nil
            }

  @optional_callbacks prepare: 2, root_attributes: 2

  @doc "Calls `module`'s `c:prepare/2`, or returns `assigns` without it."
  @spec prepare(module() | nil, module(), map()) :: map()
  def prepare(module, view, assigns) do
    if defines?(module, :prepare), do: module.prepare(view, assigns), else: assigns
  end

  @doc """
  Calls `module`'s `c:root_attributes/2`, with names and values as
  strings, or returns no attributes without it.
  """
  @spec root_attributes(module() | nil, module(), map()) :: %{String.t() => String.t() | nil}
  def root_attributes(module, view, assigns) do
    if defines?(module, :root_attributes),
      do:
        Map.new(module.root_attributes(view, assigns), fn {k, v} ->
          {to_string(k), v && to_string(v)}
        end),
      else: %{}
  end

  # The callbacks are optional, so they are looked up.
  defp defines?(nil, _callback), do: false

  defp defines?(module, callback),
    do: Code.ensure_loaded?(module) and function_exported?(module, callback, 2)
end
