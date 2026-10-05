if Code.ensure_loaded?(Ecto.Migration) do
  defmodule PhoenixReplay.Storage.Ecto.Migration do
    @moduledoc """
    Creates and upgrades the table `PhoenixReplay.Storage.Ecto` stores
    recordings in.

    Call it from a migration in your application:

        defmodule MyApp.Repo.Migrations.AddPhoenixReplay do
          use Ecto.Migration

          def up, do: PhoenixReplay.Storage.Ecto.Migration.up(version: 2)
          def down, do: PhoenixReplay.Storage.Ecto.Migration.down(version: 2)
        end

    Pin the version, so the migration does the same thing after later
    releases add versions. The table is versioned, and each PhoenixReplay
    release that changes it adds a version:

      1. the table PhoenixReplay 0.4 created
      2. `error_count`, `tab`, `viewport`, `device` and `source`, which
         the dashboard lists and filters by, and `saved_at`, which keeps its
         pages in place

    `up/1` runs every version after `:from` (default `0`), up to
    `:version` (default the latest); `down/1` reverses them. A table made by
    an earlier release is upgraded with a new migration:

        def up, do: PhoenixReplay.Storage.Ecto.Migration.up(from: 1, version: 2)
        def down, do: PhoenixReplay.Storage.Ecto.Migration.down(from: 1, version: 2)

    The module is a migration itself, creating the latest table, so tools
    such as `Ecto.Migrator.run/4` can run it directly.
    """

    use Ecto.Migration

    @table :phoenix_replay_recordings
    @latest 2

    @doc "The latest version of the table."
    @spec latest() :: pos_integer()
    def latest, do: @latest

    @doc "Runs the versions after `:from`, up to `:version`."
    @spec up(keyword()) :: :ok
    def up(opts \\ []) do
      for version <- range(opts), do: change(version, :up)
      :ok
    end

    @doc "Reverses the versions `up/1` with the same options runs."
    @spec down(keyword()) :: :ok
    def down(opts \\ []) do
      for version <- opts |> range() |> Enum.reverse(), do: change(version, :down)
      :ok
    end

    defp range(opts),
      do: (Keyword.get(opts, :from, 0) + 1)..Keyword.get(opts, :version, @latest)//1

    defp change(1, :up) do
      create table(@table, primary_key: false) do
        add :id, :string, primary_key: true
        add :view, :string, null: false
        add :url, :text
        add :connected_at, :bigint, null: false
        add :event_count, :integer, null: false
        add :duration_ms, :integer, null: false
        add :event_names, :binary, null: false
        add :data, :binary, null: false
      end

      create index(@table, [:connected_at])
    end

    defp change(1, :down), do: drop(table(@table))

    defp change(2, :up) do
      alter table(@table) do
        # Not NULL-constrained: DuckDB cannot add such a column inside the
        # migration's transaction. Saving always writes it.
        add :error_count, :integer, default: 0
        add :tab, :string
        add :viewport, :string
        add :device, :string
        add :source, :string
        add :saved_at, :bigint
      end
    end

    defp change(2, :down) do
      alter table(@table) do
        remove :error_count
        remove :tab
        remove :viewport
        remove :device
        remove :source
        remove :saved_at
      end
    end
  end
end
