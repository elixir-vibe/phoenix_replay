defmodule PhoenixReplay.Recording.Summary do
  @moduledoc """
  Lightweight description of a recording, used for listings and filtering.

  Storage backends return summaries without decoding full recordings.
  `event_names` are the distinct `handle_event/3` names, sorted.
  `error_count` counts the events for which `PhoenixReplay.Recording.Event.error?/1`
  holds. `tab` is the browser tab the session ran in, when the client sent
  it, shared by the sessions of one journey. `viewport`, `device` and
  `source` describe the browser and where the visit came from, as
  `PhoenixReplay.Recording.Client` names them. `saved_at` is when storage
  saved the recording, in Unix milliseconds, or `nil` before it is saved and
  for recordings saved before PhoenixReplay 0.5. `live?` is true while the
  recorded LiveView process is still running.
  """

  alias PhoenixReplay.Recording
  alias PhoenixReplay.Recording.{Client, Event}

  @type t :: %__MODULE__{
          id: Recording.id(),
          view: String.t(),
          url: String.t() | nil,
          connected_at: integer(),
          event_count: non_neg_integer(),
          event_names: [String.t()],
          error_count: non_neg_integer(),
          tab: String.t() | nil,
          viewport: Recording.viewport() | nil,
          device: String.t() | nil,
          source: String.t() | nil,
          duration_ms: non_neg_integer(),
          saved_at: integer() | nil,
          live?: boolean()
        }

  @typedoc "What a summary counts of a recording's events; see `totals/2`."
  @type totals :: %{
          event_count: non_neg_integer(),
          error_count: non_neg_integer(),
          event_names: [String.t()],
          duration_ms: non_neg_integer()
        }

  @no_totals %{event_count: 0, error_count: 0, event_names: [], duration_ms: 0}

  @enforce_keys [:id, :view, :connected_at]
  defstruct [
    :id,
    :view,
    :url,
    :connected_at,
    event_count: 0,
    event_names: [],
    error_count: 0,
    tab: nil,
    viewport: nil,
    device: nil,
    source: nil,
    duration_ms: 0,
    saved_at: nil,
    live?: false
  ]

  @doc "Summarizes a recording."
  @spec new(Recording.t(), keyword()) :: t()
  def new(%Recording{} = recording, opts \\ []) do
    summary = %__MODULE__{
      id: recording.id,
      view: inspect(recording.view),
      url: recording.url,
      connected_at: recording.connected_at,
      tab: recording.client.tab,
      viewport: recording.client.viewport,
      device: Client.device(recording.client.user_agent),
      source: Client.source(recording.client),
      saved_at: Keyword.get(opts, :saved_at),
      live?: Keyword.get(opts, :live?, false)
    }

    Map.merge(summary, totals(recording.events))
  end

  @doc """
  Counts `events` into `totals`, which start at zero: every event but
  pointer batches, which are not shown as events; the events for which
  `PhoenixReplay.Recording.Event.error?/1` holds; the distinct
  `handle_event/3` names, sorted; and the time of the last event.

  A recording flushed to storage in chunks is counted chunk by chunk.
  """
  @spec totals([Event.t()], totals()) :: totals()
  def totals(events, totals \\ @no_totals) do
    {totals, names} = Enum.reduce(events, {totals, totals.event_names}, &count/2)
    %{totals | event_names: names |> Enum.uniq() |> Enum.sort()}
  end

  defp count(%Event{} = event, {totals, names}) do
    totals = %{
      totals
      | event_count: totals.event_count + one(event.type != :pointer),
        error_count: totals.error_count + one(Event.error?(event)),
        duration_ms: max(totals.duration_ms, event.at)
    }

    {totals, event_name(event, names)}
  end

  defp one(true), do: 1
  defp one(false), do: 0

  defp event_name(%Event{type: :event, data: %{name: name}}, names), do: [name | names]
  defp event_name(_event, names), do: names

  @doc """
  When the recording reached storage: `saved_at`, or `connected_at` for
  recordings saved before PhoenixReplay 0.5 recorded it. Lists are read
  as of a moment by this time, so recordings saved later wait instead of
  shifting the rows.
  """
  @spec stored_at(t()) :: integer()
  def stored_at(%__MODULE__{saved_at: nil, connected_at: connected_at}), do: connected_at
  def stored_at(%__MODULE__{saved_at: saved_at}), do: saved_at

  @doc """
  Orders summaries most recent first. Sessions that started in the same
  millisecond are ordered by id, so pages never repeat or skip them.
  """
  @spec sort([t()]) :: [t()]
  def sort(summaries), do: Enum.sort_by(summaries, &{&1.connected_at, &1.id}, :desc)
end
