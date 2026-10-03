if Code.ensure_loaded?(Ecto.Query) do
  defmodule PhoenixReplay.Storage.Ecto do
    @moduledoc """
    Stores recordings in a database table through an Ecto repo.

    Summary columns are stored alongside the encoded recording so listing
    never decodes recordings.

    ## Options

      * `:repo` — the Ecto repo module (required)

    ## Migration

        defmodule MyApp.Repo.Migrations.CreatePhoenixReplayRecordings do
          use Ecto.Migration

          def change do
            create table(:phoenix_replay_recordings, primary_key: false) do
              add :id, :string, primary_key: true
              add :view, :string, null: false
              add :url, :text
              add :connected_at, :bigint, null: false
              add :event_count, :integer, null: false
              add :duration_ms, :integer, null: false
              add :data, :binary, null: false
            end

            create index(:phoenix_replay_recordings, [:connected_at])
          end
        end
    """

    @behaviour PhoenixReplay.Storage

    import Ecto.Query

    alias PhoenixReplay.Recording
    alias PhoenixReplay.Recording.Summary
    alias PhoenixReplay.Storage.Codec

    @table "phoenix_replay_recordings"
    @summary_fields [:id, :view, :url, :connected_at, :event_count, :duration_ms]
    @replaced_fields [:view, :url, :connected_at, :event_count, :duration_ms, :data]

    @impl true
    def save(%Recording{} = recording, opts) do
      row =
        recording
        |> Summary.new()
        |> Map.take(@summary_fields)
        |> Map.put(:data, Codec.encode(recording))

      repo(opts).insert_all(@table, [row],
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
      query =
        from(r in @table,
          order_by: [desc: r.connected_at],
          select: map(r, ^@summary_fields)
        )

      Enum.map(repo(opts).all(query), &struct!(Summary, &1))
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

    defp repo(opts), do: Keyword.fetch!(opts, :repo)
  end
end
