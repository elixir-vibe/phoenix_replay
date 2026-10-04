defmodule PhoenixReplay.Test.EctoMigration do
  @moduledoc false
  # The migration PhoenixReplay.Storage.Ecto documents, run against each
  # database the storage is tested on.

  use Ecto.Migration

  def change do
    create table(:phoenix_replay_recordings, primary_key: false) do
      add(:id, :string, primary_key: true)
      add(:view, :string, null: false)
      add(:url, :text)
      add(:connected_at, :bigint, null: false)
      add(:event_count, :integer, null: false)
      add(:duration_ms, :integer, null: false)
      add(:error_count, :integer, null: false, default: 0)
      add(:tab, :string)
      add(:viewport, :string)
      add(:device, :string)
      add(:source, :string)
      add(:event_names, :binary, null: false)
      add(:data, :binary, null: false)
    end

    create(index(:phoenix_replay_recordings, [:connected_at]))
  end
end
