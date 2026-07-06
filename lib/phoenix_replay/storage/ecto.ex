if Code.ensure_loaded?(Ecto) do
  defmodule PhoenixReplay.Storage.Ecto do
    @moduledoc """
    Ecto-based storage backend. Stores recordings in a database table.

    Requires `ecto_sql` as a dependency of the host application.

    ## Options

      * `:repo` — the Ecto repo module (required)
      * `:format` — `:etf` (default) or `:json` — controls the serialization
        format of the `data` column

    ## Migration

    Create the table with:

        defmodule MyApp.Repo.Migrations.CreatePhoenixReplayRecordings do
          use Ecto.Migration

          def change do
            create table(:phoenix_replay_recordings, primary_key: false) do
              add :id, :string, primary_key: true
              add :view, :string, null: false
              add :connected_at, :bigint, null: false
              add :event_count, :integer, null: false, default: 0
              add :data, :binary, null: false

              timestamps(type: :utc_datetime)
            end
          end
        end
    """

    @behaviour PhoenixReplay.Storage

    alias PhoenixReplay.Storage.Serializer

    import Ecto.Query

    defp repo(opts), do: Keyword.fetch!(opts, :repo)
    defp format(opts), do: Keyword.get(opts, :format, :etf)
    defp table, do: "phoenix_replay_recordings"

    @impl true
    def init(_opts), do: :ok

    @impl true
    def save(recording, opts) do
      with {:ok, data} <- Serializer.encode(recording, format(opts)) do
        now = DateTime.utc_now() |> DateTime.truncate(:second)

        repo(opts).insert_all(
          table(),
          [
            %{
              id: recording.id,
              view: inspect(recording.view),
              connected_at: recording.connected_at,
              event_count: length(recording.events),
              data: data,
              inserted_at: now,
              updated_at: now
            }
          ],
          on_conflict: {:replace, [:data, :event_count, :updated_at]},
          conflict_target: :id
        )

        :ok
      end
    end

    @impl true
    def get(id, opts) do
      query = from(r in table(), where: r.id == ^id, select: r.data)

      case repo(opts).one(query) do
        nil -> :error
        data -> Serializer.decode(data, format(opts))
      end
    end

    @impl true
    def list(opts) do
      query = from(r in table(), order_by: [desc: r.connected_at], select: r.data)

      repo(opts).all(query)
      |> Enum.flat_map(fn data ->
        case Serializer.decode(data, format(opts)) do
          {:ok, recording} -> [recording]
          {:error, _reason} -> []
        end
      end)
    end

    @impl true
    def list_summaries(opts) do
      query =
        from(r in table(),
          order_by: [desc: r.connected_at],
          select: %{
            id: r.id,
            view: r.view,
            connected_at: r.connected_at,
            event_count: r.event_count
          }
        )

      Enum.map(repo(opts).all(query), fn summary ->
        %{
          id: summary.id,
          view: module_from_string(summary.view),
          url: nil,
          connected_at: summary.connected_at,
          event_count: summary.event_count,
          duration_ms: nil,
          active?: false
        }
      end)
    end

    @impl true
    def delete(id, opts) do
      query = from(r in table(), where: r.id == ^id)
      repo(opts).delete_all(query)
      :ok
    end

    @impl true
    def clear(opts) do
      repo(opts).delete_all(from(r in table()))
      :ok
    end

    defp module_from_string(name) when is_binary(name) do
      name
      |> String.trim_leading("Elixir.")
      |> then(&String.to_existing_atom("Elixir." <> &1))
    rescue
      _ in [ArgumentError] -> name
    end
  end
end
