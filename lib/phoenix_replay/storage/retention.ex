defmodule PhoenixReplay.Storage.Retention do
  @moduledoc """
  Deletes stored recordings beyond the configured age or count.

  Runs every `retention.interval` milliseconds when `:max_age` or
  `:max_count` is configured; otherwise the process stays idle. Recordings
  still in the buffer are never pruned.
  """

  use GenServer

  alias PhoenixReplay.{Catalog, Config, Storage}
  alias PhoenixReplay.Recording.Summary

  @doc "Starts the retention process registered under its module name."
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  @doc "Deletes every stored recording that `expired/3` selects. Returns the deleted ids."
  @spec prune(Config.t(), integer()) :: [PhoenixReplay.Recording.id()]
  def prune(%Config{storage: storage, retention: retention}, now \\ now()) do
    ids = storage |> Storage.list() |> expired(retention, now) |> Enum.map(& &1.id)
    Enum.each(ids, &Storage.delete(storage, &1))
    :ok = notify(ids)
    ids
  end

  @doc """
  Selects summaries older than `max_age` or beyond the newest `max_count`.

  `summaries` must be ordered most recent first.
  """
  @spec expired([Summary.t()], Config.retention(), integer()) :: [Summary.t()]
  def expired(summaries, %{max_age: max_age, max_count: max_count}, now) do
    summaries
    |> Enum.with_index()
    |> Enum.filter(fn {summary, index} ->
      too_old?(summary, max_age, now) or too_many?(index, max_count)
    end)
    |> Enum.map(fn {summary, _index} -> summary end)
  end

  @impl true
  def init(_opts) do
    schedule(Config.load())
    {:ok, nil}
  end

  @impl true
  def handle_info(:prune, state) do
    config = Config.load()
    prune(config)
    schedule(config)
    {:noreply, state}
  end

  defp schedule(%Config{retention: %{max_age: nil, max_count: nil}}), do: :ok

  defp schedule(%Config{retention: %{interval: interval}}) do
    Process.send_after(self(), :prune, interval)
    :ok
  end

  defp notify([]), do: :ok
  defp notify(_ids), do: Catalog.broadcast_change()

  defp too_old?(_summary, nil, _now), do: false
  defp too_old?(summary, max_age, now), do: now - summary.connected_at > max_age

  defp too_many?(_index, nil), do: false
  defp too_many?(index, max_count), do: index >= max_count

  defp now, do: System.system_time(:millisecond)
end
