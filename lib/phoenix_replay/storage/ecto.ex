if Code.ensure_loaded?(Ecto.Query) do
  defmodule PhoenixReplay.Storage.Ecto do
    @moduledoc """
    Stores recordings in a database table through an Ecto repo.

    Summary columns are stored alongside the encoded recording so listing
    never decodes recordings. `event_names` holds the summary's event names
    in the same encoding as `data`, and the `phoenix_replay_marks` table
    the moments each recording reached, so SQL can filter and count them.

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

          def up, do: PhoenixReplay.Storage.Ecto.Migration.up(version: 3)
          def down, do: PhoenixReplay.Storage.Ecto.Migration.down(version: 3)
        end
    """

    @behaviour PhoenixReplay.Storage

    import Ecto.Query

    alias PhoenixReplay.Recording
    alias PhoenixReplay.Recording.{Client, Filter, Summary}
    alias PhoenixReplay.Storage.Codec

    @table "phoenix_replay_recordings"
    @marks "phoenix_replay_marks"
    # Criteria and values that are columns of their own.
    @columns [:view, :source, :medium, :campaign, :device_type, :browser]
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
      :device_type,
      :browser,
      :source,
      :medium,
      :campaign,
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
      :device_type,
      :browser,
      :source,
      :medium,
      :campaign,
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

      marks =
        for {name, count} <- summary.marks,
            do: %{recording_id: recording.id, name: name, count: count}

      # Marks first, without a transaction, which DuckDB cannot nest: if
      # saving stops between them, the marks are of no recording, and
      # every query of marks joins them to their recording.
      repo = repo(opts)
      repo.delete_all(from(m in @marks, where: m.recording_id == ^recording.id))
      if marks != [], do: repo.insert_all(@marks, marks)

      repo.insert_all(@table, [row],
        on_conflict: {:replace, @replaced_fields},
        conflict_target: :id
      )

      :ok
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
      repo = repo(opts)

      from(r in @table,
        order_by: [desc: r.connected_at, desc: r.id],
        select: map(r, ^[:event_names | @summary_fields])
      )
      |> repo.all()
      |> Enum.map(&to_summary/1)
      |> put_marks(repo.all(from(m in @marks, select: {m.recording_id, m.name, m.count})))
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
        |> summaries(opts)

      {summaries, total}
    end

    # Text search and the event filter look at event names, which SQL cannot
    # read; the other criteria narrow the rows first, and are not checked
    # again.
    def query(%Filter{} = filter, page_opts, opts) do
      {page, total} =
        %{filter | event: nil, query: nil}
        |> matching(page_opts)
        |> order_by(desc: :connected_at, desc: :id)
        |> select([r], map(r, ^[:event_names | @summary_fields]))
        |> repo(opts).all()
        |> Enum.map(&to_summary/1)
        |> Filter.page(%Filter{query: filter.query, event: filter.event}, page_opts)

      {with_marks(page, opts), total}
    end

    # The criteria SQL can check: all but text and the event name.
    defp matching(filter, page_opts) do
      columns = Enum.map(@columns, &{&1, Map.fetch!(filter, &1)})

      columns
      |> Enum.concat(
        mark: filter.mark,
        started_after: Filter.started_after(filter, Keyword.fetch!(page_opts, :now)),
        from: filter.from,
        to: filter.to,
        longer_than: filter.longer_than,
        min_events: filter.min_events,
        errors: filter.errors,
        tab: filter.tab,
        until: page_opts[:until],
        since: page_opts[:since]
      )
      |> Enum.reject(fn {_criterion, value} -> value in [nil, false] end)
      |> Enum.reduce(from(r in @table, as: :recording), fn {criterion, value}, query ->
        where(query, ^criterion(criterion, value))
      end)
    end

    defp criterion(column, value) when column in @columns,
      do: dynamic([r], field(r, ^column) == ^value)

    defp criterion(:mark, name) do
      marked =
        from(m in @marks,
          where: m.recording_id == parent_as(:recording).id and m.name == ^name,
          select: 1
        )

      dynamic(exists(marked))
    end

    defp criterion(:started_after, ms), do: dynamic([r], r.connected_at >= ^ms)
    defp criterion(:from, ms), do: dynamic([r], r.connected_at >= ^ms)
    defp criterion(:to, ms), do: dynamic([r], r.connected_at <= ^ms)
    defp criterion(:longer_than, seconds), do: dynamic([r], r.duration_ms >= ^(seconds * 1_000))
    defp criterion(:min_events, count), do: dynamic([r], r.event_count >= ^count)
    defp criterion(:errors, true), do: dynamic([r], r.error_count > 0)
    defp criterion(:tab, tab), do: dynamic([r], r.tab == ^tab)
    defp criterion(:until, ms), do: dynamic([r], coalesce(r.saved_at, r.connected_at) <= ^ms)
    defp criterion(:since, ms), do: dynamic([r], coalesce(r.saved_at, r.connected_at) > ^ms)

    # Event names are stored encoded, so they are counted among this many
    # of the most recent recordings matching the rest of the filter.
    @value_rows 500

    @impl true
    def values(column, %Filter{event: nil, query: nil} = filter, page_opts, opts)
        when column in @columns do
      filter
      |> Map.put(column, nil)
      |> matching(page_opts)
      |> where([r], not is_nil(field(r, ^column)))
      |> group_by([r], field(r, ^column))
      |> order_by([r], desc: count(r.id), asc: field(r, ^column))
      |> limit(^Keyword.fetch!(page_opts, :limit))
      |> select([r], {field(r, ^column), count(r.id)})
      |> repo(opts).all()
    end

    def values(:mark, %Filter{event: nil, query: nil} = filter, page_opts, opts) do
      %{filter | mark: nil}
      |> matching(page_opts)
      |> join(:inner, [r], m in @marks, on: m.recording_id == r.id)
      |> group_by([_r, m], m.name)
      |> order_by([r, m], desc: count(r.id), asc: m.name)
      |> limit(^Keyword.fetch!(page_opts, :limit))
      |> select([r, m], {m.name, count(r.id)})
      |> repo(opts).all()
    end

    # Text search and the event filter read event names too, which SQL
    # cannot; the other criteria narrow the rows first.
    def values(field, %Filter{} = filter, page_opts, opts) do
      %{filter | event: nil, query: nil}
      |> Map.put(field, nil)
      |> matching(page_opts)
      |> order_by(desc: :connected_at, desc: :id)
      |> limit(@value_rows)
      |> summaries(opts)
      |> Filter.count_values(
        field,
        %Filter{query: filter.query, event: filter.event},
        page_opts[:now],
        page_opts[:limit]
      )
    end

    @impl true
    def histogram(%Filter{event: nil, query: nil} = filter, size, page_opts, opts) do
      filter
      |> matching(page_opts)
      |> group_by(selected_as(:bucket))
      |> order_by(selected_as(:bucket))
      |> select([r], {
        selected_as(fragment("? - (? % ?)", r.connected_at, r.connected_at, ^size), :bucket),
        count(r.id),
        sum(fragment("CASE WHEN ? > 0 THEN 1 ELSE 0 END", r.error_count))
      })
      |> repo(opts).all()
      |> Enum.map(fn {start, sessions, errors} -> {start, sessions, errors || 0} end)
    end

    def histogram(%Filter{} = filter, size, page_opts, opts) do
      %{filter | event: nil, query: nil}
      |> matching(page_opts)
      |> summaries(opts)
      |> Filter.histogram(
        %Filter{query: filter.query, event: filter.event},
        size,
        page_opts[:now]
      )
    end

    @impl true
    def delete(id, opts) do
      repo(opts).delete_all(from(r in @table, where: r.id == ^id))
      repo(opts).delete_all(from(m in @marks, where: m.recording_id == ^id))
      :ok
    end

    @impl true
    def clear(opts) do
      repo(opts).delete_all(@marks)
      repo(opts).delete_all(@table)
      :ok
    end

    # The summaries of the rows a query selects, with their marks.
    defp summaries(query, opts) do
      query
      |> select([r], map(r, ^[:event_names | @summary_fields]))
      |> repo(opts).all()
      |> Enum.map(&to_summary/1)
      |> with_marks(opts)
    end

    defp with_marks([], _opts), do: []

    defp with_marks(summaries, opts) do
      ids = Enum.map(summaries, & &1.id)

      marks =
        repo(opts).all(
          from(m in @marks,
            where: m.recording_id in ^ids,
            select: {m.recording_id, m.name, m.count}
          )
        )

      put_marks(summaries, marks)
    end

    defp put_marks(summaries, marks) do
      by_id =
        Enum.group_by(marks, &elem(&1, 0), fn {_id, name, count} -> {name, count} end)

      Enum.map(summaries, &%{&1 | marks: Map.new(Map.get(by_id, &1.id, []))})
    end

    defp to_summary(%{event_names: encoded} = row) do
      {:ok, names} = Codec.decode(encoded, :list)

      Summary
      |> struct!(%{row | event_names: names, viewport: Client.decode_viewport(row.viewport)})
      |> Summary.upgrade()
    end

    defp repo(opts), do: Keyword.fetch!(opts, :repo)
  end
end
