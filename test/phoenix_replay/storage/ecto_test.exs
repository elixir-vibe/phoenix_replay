defmodule PhoenixReplay.Storage.EctoTest do
  use ExUnit.Case, async: false

  alias PhoenixReplay.Storage.Ecto, as: EctoStorage
  alias PhoenixReplay.Test.Fixtures

  defmodule Repo do
    use Ecto.Repo, otp_app: :phoenix_replay, adapter: Ecto.Adapters.SQLite3
  end

  @moduletag :tmp_dir

  setup %{tmp_dir: tmp_dir} do
    start_supervised!({Repo, database: Path.join(tmp_dir, "replay.db"), pool_size: 1, log: false})

    Ecto.Adapters.SQL.query!(Repo, """
    CREATE TABLE phoenix_replay_recordings (
      id TEXT PRIMARY KEY,
      view TEXT NOT NULL,
      url TEXT,
      connected_at INTEGER NOT NULL,
      event_count INTEGER NOT NULL,
      duration_ms INTEGER NOT NULL,
      event_names BLOB NOT NULL,
      data BLOB NOT NULL
    )
    """)

    %{opts: [repo: Repo]}
  end

  test "saves, fetches and lists summaries newest first", %{opts: opts} do
    older = Fixtures.counter_recording(id: "older", connected_at: 1)
    newer = Fixtures.counter_recording(id: "newer", connected_at: 2)

    assert :ok = EctoStorage.save(older, opts)
    assert :ok = EctoStorage.save(newer, opts)
    assert :ok = EctoStorage.save(newer, opts)

    assert EctoStorage.fetch("older", opts) == {:ok, older}
    assert EctoStorage.fetch("missing", opts) == {:error, :not_found}

    assert [
             %{
               id: "newer",
               view: "PhoenixReplay.Test.Live.Counter",
               event_count: 6,
               event_names: ["inc"],
               duration_ms: 2001
             },
             %{id: "older"}
           ] = EctoStorage.list(opts)
  end

  test "deletes one or all recordings", %{opts: opts} do
    for id <- ~w(a b), do: EctoStorage.save(Fixtures.counter_recording(id: id), opts)

    assert :ok = EctoStorage.delete("a", opts)
    assert [%{id: "b"}] = EctoStorage.list(opts)
    assert :ok = EctoStorage.clear(opts)
    assert EctoStorage.list(opts) == []
  end
end
