defmodule PhoenixReplay.Web.Rendering do
  @moduledoc """
  Renders recorded views and LiveComponents with recorded assigns.

  Recorded templates are foreign code rendered with assigns that may be
  incomplete at a given position. HEEx evaluates assigns lazily while
  LiveView computes the diff, so `render_error/2` evaluates a template up
  front to report failures before LiveView sees them.

  `rewrite/2` replaces every LiveComponent in a rendered tree with
  `PhoenixReplay.Web.Live.ReplayComponent`, which renders the original
  module with the component's recorded assigns. Components need no changes
  to be replayed.
  """

  require Logger

  alias Phoenix.LiveView.{Component, Comprehension, Rendered}
  alias PhoenixReplay.Web.Live.ReplayComponent

  @type states :: %{{module(), term()} => map()}

  @doc """
  Renders `module` with `assigns`, returning a short description of the
  error when any part of the template fails to evaluate, or `nil`.

  Exception messages can include every assign, so the description names a
  missing assign or keeps the first line of the message; the full message
  is logged at the debug level.
  """
  @spec render_error(module(), map()) :: String.t() | nil
  # credo:disable-for-next-line ExSlop.Check.Warning.BlanketRescue
  def render_error(module, assigns) do
    assigns |> module.render() |> evaluate()
    nil
  rescue
    # reach:disable-next-line bare_rescue -- recorded templates are foreign code rendered with partial assigns
    exception ->
      Logger.debug(
        "PhoenixReplay: #{inspect(module)} failed to render: #{Exception.message(exception)}"
      )

      describe(exception)
  end

  @max_description 200

  @doc false
  @spec describe(Exception.t()) :: String.t()
  def describe(%KeyError{key: key, term: %{__changed__: _changed}}) when is_atom(key),
    do: "the recording has no @#{key}"

  def describe(%KeyError{key: key}), do: "key #{inspect(key)} not found"

  def describe(exception) do
    line = exception |> Exception.message() |> String.split("\n", parts: 2) |> hd()

    if String.length(line) > @max_description,
      do: String.slice(line, 0, @max_description) <> "…",
      else: line
  end

  @doc "Routes every LiveComponent in `rendered` through the replay component."
  @spec rewrite(Rendered.t(), states()) :: Rendered.t()
  def rewrite(%Rendered{dynamic: dynamic} = rendered, states) do
    %{
      rendered
      | dynamic: fn track? -> Enum.map(dynamic.(track?), &rewrite_dynamic(&1, states)) end
    }
  end

  defp rewrite_dynamic(%Rendered{} = rendered, states), do: rewrite(rendered, states)

  defp rewrite_dynamic(%Comprehension{entries: entries} = comprehension, states) do
    entries =
      Enum.map(entries, fn {key, vars, render} ->
        {key, vars,
         fn vars_changed, track? ->
           Enum.map(render.(vars_changed, track?), &rewrite_dynamic(&1, states))
         end}
      end)

    %{comprehension | entries: entries}
  end

  defp rewrite_dynamic(%Component{component: ReplayComponent} = component, _states), do: component

  defp rewrite_dynamic(%Component{component: module, id: id, assigns: assigns}, states) do
    %Component{
      component: ReplayComponent,
      id: {module, id},
      assigns: Map.merge(assigns, ReplayComponent.replay_assigns(module, id, states))
    }
  end

  defp rewrite_dynamic(dynamic, _states), do: dynamic

  defp evaluate(%Rendered{dynamic: dynamic}), do: Enum.each(dynamic.(false), &evaluate/1)

  defp evaluate(%Comprehension{entries: entries}) do
    Enum.each(entries, fn {_key, _vars, render} ->
      Enum.each(render.(%{}, false), &evaluate/1)
    end)
  end

  defp evaluate(_dynamic), do: :ok
end
