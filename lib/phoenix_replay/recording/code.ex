defmodule PhoenixReplay.Recording.Code do
  @moduledoc """
  Which code a recording was made with, as its `code`, so the player can
  say what changed since.

  Replay renders today's code with the assigns recorded then. A recording
  keeps:

    * `release` — the name of the deploy, from the `:release` config, such
      as a commit, or the version of the view's application. For people
      and the recording list's filter; nothing is decided by it.
    * `modules` — the MD5 of each module that rendered the session, its
      view and its LiveComponents, as `module_info(:md5)` gives it, which
      changes whenever the module's code does.
    * `deps` — the versions of the dependencies that render: Phoenix,
      LiveView, `phoenix_html`, `phoenix_template`, and any dependency of
      the view's application built on LiveView, such as a component
      library.

  Reading them costs a few function calls when a session starts; the
  dependency versions are read once per application.
  """

  @type t :: %{
          release: String.t() | nil,
          modules: %{module() => String.t()},
          deps: %{atom() => String.t()}
        }

  @typedoc "What changed since a recording, as `changes/1` tells."
  @type changes :: %{
          modules: [module()],
          deps: [{atom(), String.t(), String.t() | nil}]
        }

  @rendering [:phoenix, :phoenix_live_view, :phoenix_html, :phoenix_template]

  @doc """
  The code `view` runs now: the release named `release`, or its
  application's version, the view's MD5 and the rendering dependencies.
  """
  @spec of(module(), String.t() | nil) :: t()
  def of(view, release) do
    app = Application.get_application(view)

    %{
      release: release || version(app),
      modules: %{view => md5(view)},
      deps: deps(app)
    }
  end

  @doc "Adds the MD5 of `modules`, such as the LiveComponents a session rendered."
  @spec with_modules(t() | nil, [module()]) :: t() | nil
  def with_modules(nil, _modules), do: nil

  def with_modules(code, modules) do
    added = for module <- modules, hash = md5(module), hash != nil, into: %{}, do: {module, hash}
    %{code | modules: Map.merge(added, code.modules)}
  end

  @doc """
  What changed since the recording was made: its modules whose code is
  different now, or that are gone, and its rendering dependencies at
  another version now, as `{dep, then, now}`. A recording made before
  code was recorded has no changes to tell.
  """
  @spec changes(t() | nil) :: changes()
  def changes(nil), do: %{modules: [], deps: []}

  def changes(%{modules: modules, deps: deps}) do
    changed = for {module, hash} <- modules, md5(module) != hash, do: module

    moved =
      for {dep, then} <- Enum.sort(deps), version(dep) != then, do: {dep, then, version(dep)}

    %{modules: Enum.sort(changed), deps: moved}
  end

  defp md5(module) do
    if Code.ensure_loaded?(module),
      do: module.module_info(:md5) |> Base.encode16(case: :lower)
  end

  defp version(nil), do: nil

  defp version(app) do
    case Application.spec(app, :vsn) do
      nil -> nil
      vsn -> List.to_string(vsn)
    end
  end

  # Read once per application: they change only with a restart.
  defp deps(nil), do: %{}

  defp deps(app) do
    key = {__MODULE__, :deps, app}

    case :persistent_term.get(key, nil) do
      nil ->
        deps = for dep <- rendering(app), version(dep), into: %{}, do: {dep, version(dep)}
        :persistent_term.put(key, deps)
        deps

      deps ->
        deps
    end
  end

  # The usual rendering dependencies, and those of the app built on LiveView.
  defp rendering(app) do
    built_on_live_view =
      for dep <- Application.spec(app, :applications) || [],
          :phoenix_live_view in (Application.spec(dep, :applications) || []),
          do: dep

    Enum.uniq(@rendering ++ built_on_live_view)
  end
end
