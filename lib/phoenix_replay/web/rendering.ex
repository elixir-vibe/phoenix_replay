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

  @max_description 200
  # Assigns LiveView keeps for itself, which `assign/2` refuses.
  @reserved [:flash, :uploads, :streams, :socket, :myself]

  @doc """
  Renders a recorded view with `assigns`: with its `replay_render/1` when
  it defines one, with `render/1` otherwise, inside its layout, as
  LiveView renders it.

  `:layout` is the layout the recording kept, `PhoenixReplay.Recording`'s
  `layout`: a `{module, template}` pair of names, or `false` for none.
  Without it, as in recordings made before it was kept, the view renders
  in the layout its `use Phoenix.LiveView, layout: ...` names. A layout
  module that no longer exists is left out.

  `replay_render/1` is an optional callback for views whose live render
  depends on code in the browser, such as a client-side component whose
  state the server never sees. It receives the same assigns `render/1`
  would, plus the client state the browser reported up to this point in
  `PhoenixReplay.Recording.State.assign/0`, `%{key => merged changes}`,
  and returns a rendered template the replay frame can show without that
  code.

  It is rendered in full on every step, without change tracking: a view
  typically derives assigns from the reported state with `assign/3`, and
  tracking would compare them with the recorded assigns, not with the
  previous step, so a value that went back to what was recorded would stay
  stale on the page.
  """
  @spec render(module(), map(), keyword()) :: Phoenix.LiveView.Rendered.t()
  def render(view, assigns, opts \\ []) do
    loaded? = Code.ensure_loaded?(view)

    # The callback of PhoenixReplay.Replay.View is optional, so it is looked up.
    inner =
      if loaded? and function_exported?(view, :replay_render, 1),
        do: view.replay_render(Map.put(assigns, :__changed__, nil)),
        else: view.render(assigns)

    case layout(view, loaded?, Keyword.get(opts, :layout)) do
      {module, template} -> in_layout(inner, module, template, assigns)
      nil -> inner
    end
  end

  defp layout(_view, _loaded?, false), do: nil

  defp layout(_view, _loaded?, {module, template}) do
    module = String.to_existing_atom("Elixir." <> module)
    if Code.ensure_loaded?(module), do: {module, template}
  rescue
    # A layout module renamed or deleted since the session was recorded.
    ArgumentError -> nil
  end

  defp layout(view, loaded?, nil) do
    if loaded? and function_exported?(view, :__live__, 0) do
      case view.__live__()[:layout] do
        {module, template} -> {module, to_string(template)}
        _none -> nil
      end
    end
  end

  # As LiveView renders a view's layout: with the view as `@inner_content`.
  defp in_layout(inner, module, template, assigns) do
    assigns = Map.put(assigns, :inner_content, inner)

    # `replay_render/1` renders without change tracking, with `__changed__`
    # nil; only a tracked render marks the content as changed.
    assigns =
      if is_map(assigns[:__changed__]),
        do: put_in(assigns.__changed__[:inner_content], true),
        else: assigns

    Phoenix.Template.render(module, template, "html", assigns)
  end

  @doc """
  Renders `module` with `assigns`, returning a short description of the
  error when any part of the template fails to evaluate, or `nil`.

  Exception messages can include every assign, so the description names a
  missing assign or keeps the first line of the message; the full message
  is logged at the debug level.
  """
  @spec render_error(module(), map(), keyword()) :: String.t() | nil
  def render_error(module, assigns, opts \\ []) do
    case render_check(module, assigns, opts) do
      :ok -> nil
      {:missing, key} -> "the recording has no @#{key}"
      {:error, description} -> description
    end
  end

  @doc """
  Renders `module` with `assigns`, as `render_error/2` does, telling an
  assign the recording lacks, such as one the template began to read after
  the session was recorded, from other failures: `{:missing, key}`, or
  `{:error, description}`. Takes `render/3`'s options.
  """
  @spec render_check(module(), map(), keyword()) ::
          :ok | {:missing, atom()} | {:error, String.t()}
  # credo:disable-for-next-line ExSlop.Check.Warning.BlanketRescue
  def render_check(module, assigns, opts \\ []) do
    module |> render(assigns, opts) |> evaluate()
    :ok
  rescue
    # reach:disable-next-line bare_rescue -- recorded templates are foreign code rendered with partial assigns
    exception ->
      Logger.debug(
        "PhoenixReplay: #{inspect(module)} failed to render: #{Exception.message(exception)}"
      )

      case exception do
        %KeyError{key: key, term: %{__changed__: _changed}}
        when is_atom(key) and key not in @reserved ->
          {:missing, key}

        exception ->
          {:error, describe(exception)}
      end
  end

  @doc """
  Describes why a recorded template failed to render, in a line short
  enough for the player: a missing assign is named as such.
  """
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

  @doc "Leaves out of recorded `assigns` those LiveView keeps for itself."
  @spec assignable(map()) :: map()
  def assignable(assigns), do: Map.drop(assigns, @reserved)

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
