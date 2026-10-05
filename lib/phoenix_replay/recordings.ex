defmodule PhoenixReplay.Recordings do
  @moduledoc """
  Reads and deletes recordings across the live buffer and storage.

  A recording is in exactly one place: `PhoenixReplay.Session.Buffer`
  while its session runs and until it is saved, storage afterwards.
  Changes are broadcast on `PhoenixReplay.PubSub` so the dashboard can
  refresh without polling.

  Stored recordings were redacted when they were saved. Sessions still in
  the buffer are redacted here, with their session's `PhoenixReplay.Redactor`,
  so everything read through this module shows the same values.
  """

  alias PhoenixReplay.{Config, Recording, Redactor, Storage}
  alias PhoenixReplay.Session.Buffer
  alias PhoenixReplay.Recording.Summary
  alias PhoenixReplay.Recordings.Filter

  @topic "phoenix_replay:recordings"

  @doc "Lists buffered then stored recordings, each most recent first."
  @spec list(Config.t()) :: [Summary.t()]
  def list(%Config{storage: storage}) do
    buffered = Enum.map(Buffer.summaries(), &redact_url/1)
    buffered_ids = MapSet.new(buffered, & &1.id)
    buffered ++ Enum.reject(Storage.list(storage), &MapSet.member?(buffered_ids, &1.id))
  end

  @doc "Summaries of the sessions still recording that match `filter`, most recent first."
  @spec live(Filter.t(), integer()) :: [Summary.t()]
  def live(%Filter{} = filter, now) do
    Buffer.summaries() |> Enum.map(&redact_url/1) |> Filter.apply(filter, now)
  end

  @doc """
  Reads a page of stored recordings matching `filter`, most recent first,
  and counts every match. See `t:PhoenixReplay.Recordings.Filter.page_opts/0`.

  Storage pages the recordings itself, unless `:allow` is given: a function
  that decides which summaries the reader may see. Every summary is then
  read and checked, so the count stays exact.
  """
  @spec query(Config.t(), Filter.t(), keyword()) :: {[Summary.t()], non_neg_integer()}
  def query(%Config{storage: storage}, %Filter{} = filter, opts) do
    case Keyword.pop(opts, :allow) do
      {nil, page_opts} ->
        Storage.query(storage, filter, page_opts)

      {allow, page_opts} ->
        storage |> Storage.list() |> Enum.filter(allow) |> Filter.page(filter, page_opts)
    end
  end

  @doc """
  The views and event names of recordings, for suggesting filter values.
  `allow` limits them to the summaries the reader may see.
  """
  @spec facets(Config.t(), (Summary.t() -> boolean()) | nil) :: Storage.facets()
  def facets(%Config{storage: storage}, nil) do
    live = Storage.facets_of(Buffer.summaries())
    stored = Storage.facets(storage)
    Map.merge(live, stored, fn _key, a, b -> Enum.sort(Enum.uniq(a ++ b)) end)
  end

  def facets(%Config{} = config, allow),
    do: config |> list() |> Enum.filter(allow) |> Storage.facets_of()

  @doc """
  Fetches a recording from the buffer or storage.

  A buffered session is redacted first, which can take a while with a
  detecting `PhoenixReplay.Redactor`. Pass `progress: fun` to be called
  with the number of events redacted so far and the total.
  """
  @spec fetch(Config.t(), Recording.id(), keyword()) :: {:ok, Recording.t()} | {:error, term()}
  def fetch(%Config{storage: storage}, id, opts \\ []) do
    with {:ok, recording} <- Buffer.fetch(id),
         {:ok, config} <- Buffer.config(id) do
      complete(recording, config, Keyword.take(opts, [:progress]))
    else
      :error -> Storage.fetch(storage, id)
    end
  end

  @doc """
  Completes a buffered session's recording: redacts the events still in the
  buffer and puts the chunks already flushed to storage, which were
  redacted when they were written, before them.

  Takes the `:progress` option of
  `PhoenixReplay.Redactor.redact_recording/3`.
  """
  @spec complete(Recording.t(), Config.t(), keyword()) :: {:ok, Recording.t()} | {:error, term()}
  def complete(%Recording{} = recording, %Config{} = config, opts \\ []) do
    with {:ok, redacted} <- Redactor.redact_recording(recording, config.redact, opts),
         {:ok, flushed} <- flushed_events(recording.id, config.storage) do
      {:ok, %{redacted | events: flushed ++ redacted.events}}
    end
  end

  # Events written concurrently can reach the buffer after a later one was
  # flushed; they follow the flushed events here, microseconds out of order.
  defp flushed_events(id, storage) do
    if Buffer.flushed?(id) do
      with {:ok, partial} <- Storage.fetch_partial(storage, id), do: {:ok, partial.events}
    else
      {:ok, []}
    end
  end

  @doc "Returns true while the session `id` is in the buffer and has not been saved."
  @spec live?(Recording.id()) :: boolean()
  def live?(id), do: Buffer.config(id) != :error

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

  defp redact_url(%Summary{url: nil} = summary), do: summary

  defp redact_url(%Summary{id: id, url: url} = summary) do
    with {:ok, %Config{redact: redactor}} when redactor != nil <- Buffer.config(id),
         {:ok, url} <- Redactor.redact_term(url, redactor) do
      %{summary | url: url}
    else
      {:ok, %Config{redact: nil}} -> summary
      _failed -> %{summary | url: nil}
    end
  end

  @doc "Notifies subscribers that the set of recordings changed."
  @spec broadcast_change() :: :ok
  def broadcast_change do
    Phoenix.PubSub.broadcast(PhoenixReplay.PubSub, @topic, :recordings_changed)
  end
end
