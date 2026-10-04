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
  alias PhoenixReplay.Recording.{Client, Event, Timeline}

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
    %__MODULE__{
      id: recording.id,
      view: inspect(recording.view),
      url: recording.url,
      connected_at: recording.connected_at,
      event_count: length(recording.events),
      event_names: event_names(recording.events),
      error_count: Enum.count(recording.events, &Event.error?/1),
      tab: recording.client[:tab],
      viewport: recording.client[:viewport],
      device: Client.device(recording.client[:user_agent]),
      source: Client.source(recording.client),
      duration_ms: Timeline.duration_ms(recording),
      saved_at: Keyword.get(opts, :saved_at),
      live?: Keyword.get(opts, :live?, false)
    }
  end

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

  @doc "Distinct `handle_event/3` names among `events`, sorted."
  @spec event_names([Event.t()]) :: [String.t()]
  def event_names(events) do
    names = for %{type: :event, data: %{name: name}} <- events, uniq: true, do: name
    Enum.sort(names)
  end
end
