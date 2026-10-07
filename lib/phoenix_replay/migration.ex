defmodule PhoenixReplay.Migration do
  @moduledoc """
  Adapts recordings whose assigns changed shape since, such as a
  `:dark_mode` boolean that became a `:theme`, as database migrations
  adapt rows.

  Replay renders today's templates with the assigns recorded then. An
  assign a recording lacks needs nothing: it renders as `nil`, and the
  player notes it. A migration is for an assign that is there but means
  something else now:

      defmodule MyAppWeb.ReplayMigrations.DarkModeToTheme do
        use PhoenixReplay.Migration, version: 20261007120000

        @impl true
        def up(MyAppWeb.TaskLive.Index, %{dark_mode: dark?} = assigns),
          do: Map.put_new(assigns, :theme, if(dark?, do: "dark", else: "light"))

        def up(_view_or_component, assigns), do: assigns
      end

  `c:up/2` takes the view or LiveComponent module, and the assigns it is
  about to render with; match the module in the function head. Versions
  are timestamps, as Ecto's migrations name theirs, so they sort as they
  were written.

  Migrations are found among the modules of the view's application, with
  nothing to configure. Each recording keeps the newest version it was
  made with (see `PhoenixReplay.Recording.Code`), and replay applies the
  newer ones, in order, to its view's assigns and each LiveComponent's. A
  recording made before versions were kept gets them all, so write `up/2`
  to leave assigns that already have the new shape as they are, as
  `Map.put_new/3` does.

  As with Ecto's migrations, a version says when a migration was written,
  not when it shipped: one merged after a newer one, with an older
  timestamp, is skipped for recordings made in between, whose version is
  already past it. Give a migration that lands late a fresh timestamp.
  """

  @doc """
  The assigns `module`, a view or LiveComponent, renders with today, from
  those recorded before this migration.
  """
  @callback up(module :: module(), assigns :: map()) :: map()

  @doc """
  Makes the module a migration of version `:version`, a timestamp such as
  `20261007120000`, which replay finds and orders by.
  """
  defmacro __using__(opts) do
    version = Keyword.fetch!(opts, :version)

    quote do
      @behaviour PhoenixReplay.Migration

      @doc "This migration's version, a timestamp."
      @spec __replay_migration__() :: pos_integer()
      def __replay_migration__, do: unquote(version)
    end
  end

  @typedoc "A migration module and its version."
  @type migration :: {pos_integer(), module()}

  @doc """
  The migrations of the application `module` belongs to, oldest first.
  They are read once per set of the application's modules.
  """
  @spec all(module()) :: [migration()]
  def all(module) do
    case Application.get_application(module) do
      nil -> []
      app -> of_app(app)
    end
  end

  @doc "The newest migration version of `module`'s application, or `nil` without any."
  @spec latest(module()) :: pos_integer() | nil
  def latest(module) do
    case all(module) do
      [] -> nil
      migrations -> migrations |> Enum.map(&elem(&1, 0)) |> Enum.max()
    end
  end

  @doc """
  The migrations newer than `stamp`, the version a recording was made
  with, or all of them for a recording made before versions were kept.
  """
  @spec pending([migration()], pos_integer() | nil) :: [migration()]
  def pending(migrations, nil), do: migrations

  def pending(migrations, stamp),
    do: Enum.filter(migrations, fn {version, _} -> version > stamp end)

  @doc "Applies `migrations` to the assigns of `module`, in order."
  @spec apply_to([migration()], module(), map()) :: map()
  def apply_to(migrations, module, assigns) do
    Enum.reduce(migrations, assigns, fn {_version, migration}, acc ->
      migration.up(module, acc)
    end)
  end

  defp of_app(app) do
    modules = Application.spec(app, :modules) || []
    key = {__MODULE__, app}

    case :persistent_term.get(key, nil) do
      {^modules, migrations} ->
        migrations

      _stale ->
        migrations =
          for module <- modules,
              Code.ensure_loaded?(module),
              function_exported?(module, :__replay_migration__, 0),
              do: {module.__replay_migration__(), module}

        migrations = Enum.sort(migrations)
        :persistent_term.put(key, {modules, migrations})
        migrations
    end
  end
end
