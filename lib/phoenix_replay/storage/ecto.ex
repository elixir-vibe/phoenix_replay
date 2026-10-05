if Code.ensure_loaded?(Ecto.Query) do
  defmodule PhoenixReplay.Storage.Ecto do
    @moduledoc """
    Stores recordings in a database table through an Ecto repo.

    Summary columns are stored alongside the encoded recording so listing
    never decodes recordings. `event_names` holds the summary's event names
    in the same encoding as `data`.

    The dashboard's pages are read in SQL, except when filtering by text or
    event name: event names are stored encoded, so those criteria are
    checked after reading the rows matching the others.

    Tested on PostgreSQL, SQLite (ecto_sqlite3) and DuckDB (QuackDB). MySQL
    is not supported: saving upserts on `id`, and Ecto cannot name a
    conflict target there.

    ## Options

      * `:repo` — the Ecto repo module (required)

    ## Migration

    Create the table with `PhoenixReplay.Storage.Ecto.Migration`, which also
    upgrades tables made by earlier releases:

        defmodule MyApp.Repo.Migrations.AddPhoenixReplay do
          use Ecto.Migration

          def up, do: PhoenixReplay.Storage.Ecto.Migration.up(version: 2)
          def down, do: PhoenixReplay.Storage.Ecto.Migration.down(version: 2)
        end
    """

    @behaviour PhoenixReplay.Storage

    import Ecto.Query

    alias PhoenixReplay.Recording
    alias PhoenixReplay.Recording.{Client, Summary}
    alias PhoenixReplay.Recordings.Filter
    alias PhoenixReplay.Storage.Codec

    @table "phoenix_replay_recordings"
    @summary_fields [
      :id,
      :view,
      :url,
      :connected_at,
      :event_count,
      :error_count,
      :duration_ms,
      :tab,
      :viewport,
      :device,
      :source,
      :saved_at
    ]
    @replaced_fields [
      :view,
      :url,
      :connected_at,
      :event_count,
      :error_count,
      :duration_ms,
      :tab,
      :viewport,
      :device,
      :source,
      :saved_at,
      :event_names,
      :data
    ]

    @impl true
    def save(%Recording{} = recording, opts) do
      summary = Summary.new(recording, saved_at: System.system_time(:millisecond))

      row =
        summary
        |> Map.take(@summary_fields)
        |> Map.update!(:viewport, &Client.encode_viewport/1)
        |> Map.put(:event_names, Codec.encode(summary.event_names))
        |> Map.put(:data, Codec.encode(recording))

      repo(opts).insert_all(@table, [row],
        on_conflict: {:replace, @replaced_fields},
        conflict_target: :id
      )

      :ok
    rescue
      # A database error, such as a dropped connection, is a failed save the
      # finalizer retries, not a crash.
      error -> {:error, error}
    end

    @impl true
    def fetch(id, opts) do
      case repo(opts).one(from(r in @table, where: r.id == ^id, select: r.data)) do
        nil -> {:error, :not_found}
        data -> Codec.decode(data, Recording)
      end
    end

    @impl true
    def list(opts) do
      query =
        from(r in @table,
          order_by: [desc: r.connected_at, desc: r.id],
          select: map(r, ^[:event_names | @summary_fields])
        )

      Enum.map(repo(opts).all(query), &to_summary/1)
    end

    @impl true
    def query(%Filter{event: nil, query: nil} = filter, page_opts, opts) do
      matching = matching(filter, page_opts)
      total = repo(opts).aggregate(matching, :count)

      summaries =
        matching
        |> order_by(desc: :connected_at, desc: :id)
        |> offset(^Keyword.get(page_opts, :offset, 0))
        |> limit(^Keyword.fetch!(page_opts, :limit))
        |> select([r], map(r, ^[:event_names | @summary_fields]))
        |> repo(opts).all()
        |> Enum.map(&to_summary/1)

      {summaries, total}
    end

    # Text search and the event filter look at event names, which SQL cannot
    # read; the other criteria narrow the rows first.
    def query(%Filter{} = filter, page_opts, opts) do
      %{filter | event: nil, query: nil}
      |> matching(page_opts)
      |> order_by(desc: :connected_at, desc: :id)
      |> select([r], map(r, ^[:event_names | @summary_fields]))
      |> repo(opts).all()
      |> Enum.map(&to_summary/1)
      |> Filter.page(filter, page_opts)
    end

    # The criteria SQL can check: all but text and the event name.
    defp matching(filter, page_opts) do
      now = Keyword.fetch!(page_opts, :now)

      [
        filter.view && dynamic([r], r.view == ^filter.view),
        (after_ms = Filter.started_after(filter, now)) &&
          dynamic([r], r.connected_at >= ^after_ms),
        filter.min_events && dynamic([r], r.event_count >= ^filter.min_events),
        filter.errors && dynamic([r], r.error_count > 0),
        filter.tab && dynamic([r], r.tab == ^filter.tab),
        (until = page_opts[:until]) &&
          dynamic([r], coalesce(r.saved_at, r.connected_at) <= ^until),
        (since = page_opts[:since]) &&
          dynamic([r], coalesce(r.saved_at, r.connected_at) > ^since)
      ]
      |> Enum.filter(& &1)
      |> Enum.reduce(from(r in @table), &where(&2, ^&1))
    end

    # Event names of the most recent recordings only: they are stored encoded.
    @facet_rows 500

    @impl true
    def facets(opts) do
      views = repo(opts).all(from(r in @table, distinct: true, order_by: r.view, select: r.view))

      names =
        from(r in @table,
          order_by: [desc: r.connected_at],
          limit: @facet_rows,
          select: r.event_names
        )
        |> repo(opts).all()
        |> Enum.flat_map(fn encoded -> elem(Codec.decode(encoded, :list), 1) end)
        |> Enum.uniq()
        |> Enum.sort()

      %{views: views, event_names: names}
    end

    @impl true
    def delete(id, opts) do
      repo(opts).delete_all(from(r in @table, where: r.id == ^id))
      :ok
    end

    @impl true
    def clear(opts) do
      repo(opts).delete_all(@table)
      :ok
    end

    defp to_summary(%{event_names: encoded} = row) do
      {:ok, names} = Codec.decode(encoded, :list)

      struct!(Summary, %{row | event_names: names, viewport: Client.decode_viewport(row.viewport)})
    end

    defp repo(opts), do: Keyword.fetch!(opts, :repo)
  end
end
