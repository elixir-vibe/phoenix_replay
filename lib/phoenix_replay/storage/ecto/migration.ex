if Code.ensure_loaded?(Ecto.Migration) do
  defmodule PhoenixReplay.Storage.Ecto.Migration do
    @moduledoc """
    Creates and upgrades the table `PhoenixReplay.Storage.Ecto` stores
    recordings in.

    Call it from a migration in your application:

        defmodule MyApp.Repo.Migrations.AddPhoenixReplay do
          use Ecto.Migration

          def up, do: PhoenixReplay.Storage.Ecto.Migration.up(version: 4)
          def down, do: PhoenixReplay.Storage.Ecto.Migration.down(version: 4)
        end

    Pin the version, so the migration does the same thing after later
    releases add versions. The table is versioned, and each PhoenixReplay
    release that changes it adds a version:

      1. the table PhoenixReplay 0.4 created
      2. `error_count`, `tab`, `viewport`, `device` and `source`, which
         the dashboard lists and filters by, and `saved_at`, which keeps its
         pages in place
      3. `medium`, `campaign`, `device_type`, `browser` and `release`, and the
         `phoenix_replay_marks` table of the moments each session reached,
         all of which the dashboard filters by, and an index on `view`. Rows saved earlier get their
         source split into source, medium and campaign, and their device
         type from their viewport; their browser stays empty.
      4. `visit`, the visit each recording belongs to, indexed, by which the
         dashboard lists visits. Rows saved earlier have none, and each is a
         visit of its own.

    `up/1` runs every version after `:from` (default `0`), up to
    `:version` (default the latest); `down/1` reverses them. A table made by
    an earlier release is upgraded with a new migration:

        def up, do: PhoenixReplay.Storage.Ecto.Migration.up(from: 3, version: 4)
        def down, do: PhoenixReplay.Storage.Ecto.Migration.down(from: 3, version: 4)

    The module is a migration itself, creating the latest table, so tools
    such as `Ecto.Migrator.run/4` can run it directly.
    """

    use Ecto.Migration

    import Ecto.Query, only: [from: 2]

    @table :phoenix_replay_recordings
    @marks :phoenix_replay_marks
    @latest 4

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

    defp change(3, :up) do
      alter table(@table) do
        add :medium, :string
        add :campaign, :string
        add :device_type, :string
        add :browser, :string
        add :release, :string
      end

      create table(@marks, primary_key: false) do
        add :recording_id, :string, primary_key: true
        add :name, :string, primary_key: true
        add :count, :integer, null: false
      end

      create index(@marks, [:name])
      # Each filter's value picker groups by its column; views are the most
      # common filter.
      create index(@table, [:view])
      flush()
      execute(&backfill/0, fn -> :ok end)
    end

    defp change(3, :down) do
      drop(index(@table, [:view]))
      drop(table(@marks))

      alter table(@table) do
        remove :medium
        remove :campaign
        remove :device_type
        remove :browser
        remove :release
      end
    end

    defp change(4, :up) do
      alter table(@table) do
        add :visit, :string
      end

      create index(@table, [:visit])
    end

    defp change(4, :down) do
      drop(index(@table, [:visit]))

      alter table(@table) do
        remove :visit
      end
    end

    # Fills the new columns of rows saved earlier, once per distinct value:
    # the source they held as "google / cpc / spring", and the device type
    # their viewport tells. The rules are written out here, rather than
    # called from the library, so a pinned version does the same thing
    # after later releases change how summaries are read.
    defp backfill do
      table = Atom.to_string(@table)

      for source <-
            repo().all(
              from(r in table,
                where: not is_nil(r.source) and is_nil(r.medium),
                distinct: true,
                select: r.source
              )
            ) do
        {split, medium, campaign} = split_source(source)

        repo().update_all(from(r in table, where: r.source == ^source and is_nil(r.medium)),
          set: [source: split, medium: medium, campaign: campaign]
        )
      end

      for viewport <-
            repo().all(
              from(r in table,
                where: not is_nil(r.viewport) and is_nil(r.device_type),
                distinct: true,
                select: r.viewport
              )
            ) do
        repo().update_all(from(r in table, where: r.viewport == ^viewport),
          set: [device_type: device_type(viewport)]
        )
      end
    end

    # "google / cpc / spring", or a lone referrer host or utm_source.
    defp split_source(source) do
      case String.split(source, " / ", parts: 3) do
        [source, medium | campaign] ->
          {source, medium, List.first(campaign)}

        [one] ->
          {one, if(String.contains?(one, "."), do: "referral", else: "(none)"), nil}
      end
    end

    # The kind of device a viewport stored as "390x844@3" belongs to, by
    # its width in CSS pixels.
    defp device_type(viewport) do
      with [size | _dpr] <- String.split(viewport, "@"),
           [width | _height] <- String.split(size, "x"),
           {width, ""} <- Integer.parse(width) do
        cond do
          width < 640 -> "phone"
          width < 1024 -> "tablet"
          true -> "desktop"
        end
      else
        _invalid -> nil
      end
    end
  end
end
