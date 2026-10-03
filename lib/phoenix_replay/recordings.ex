defmodule PhoenixReplay.Recordings do
  @moduledoc """
  Reads and deletes recordings across the live buffer and storage.

  A recording is in exactly one place: `PhoenixReplay.Recorder.Buffer`
  while its session runs and until it is saved, storage afterwards.
  Changes are broadcast on `PhoenixReplay.PubSub` so the dashboard can
  refresh without polling.
  """

  alias PhoenixReplay.{Config, Recording, Storage}
  alias PhoenixReplay.Recorder.Buffer
  alias PhoenixReplay.Recording.Summary

  @topic "phoenix_replay:recordings"

  @doc "Lists buffered then stored recordings, each most recent first."
  @spec list(Config.t()) :: [Summary.t()]
  def list(%Config{storage: storage}) do
    buffered = Buffer.summaries()
    buffered_ids = MapSet.new(buffered, & &1.id)
    buffered ++ Enum.reject(Storage.list(storage), &MapSet.member?(buffered_ids, &1.id))
  end

  @doc "Fetches a recording from the buffer or storage."
  @spec fetch(Config.t(), Recording.id()) :: {:ok, Recording.t()} | {:error, term()}
  def fetch(%Config{storage: storage}, id) do
    case Buffer.fetch(id) do
      {:ok, recording} -> {:ok, recording}
      :error -> Storage.fetch(storage, id)
    end
  end

  @doc "Deletes a stored recording."
  @spec delete(Config.t(), Recording.id()) :: :ok | {:error, term()}
  def delete(%Config{storage: storage}, id) do
    with :ok <- Storage.delete(storage, id), do: broadcast_change()
  end

  @doc "Deletes every stored recording."
  @spec clear(Config.t()) :: :ok | {:error, term()}
  def clear(%Config{storage: storage}) do
    with :ok <- Storage.clear(storage), do: broadcast_change()
  end

  @doc "Subscribes the caller to `:recordings_changed` messages."
  @spec subscribe() :: :ok | {:error, term()}
  def subscribe, do: Phoenix.PubSub.subscribe(PhoenixReplay.PubSub, @topic)

  @doc "Notifies subscribers that the set of recordings changed."
  @spec broadcast_change() :: :ok
  def broadcast_change do
    Phoenix.PubSub.broadcast(PhoenixReplay.PubSub, @topic, :recordings_changed)
  end
end
