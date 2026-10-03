defmodule PhoenixReplay.Recording.Summary do
  @moduledoc """
  Lightweight description of a recording, used for listings and filtering.

  Storage backends return summaries without decoding full recordings.
  `event_names` are the distinct `handle_event/3` names, sorted. `live?` is
  true while the recorded LiveView process is still running.
  """

  alias PhoenixReplay.Recording
  alias PhoenixReplay.Recording.Timeline

  @type t :: %__MODULE__{
          id: Recording.id(),
          view: String.t(),
          url: String.t() | nil,
          connected_at: integer(),
          event_count: non_neg_integer(),
          event_names: [String.t()],
          duration_ms: non_neg_integer(),
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
    duration_ms: 0,
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
      duration_ms: Timeline.duration_ms(recording),
      live?: Keyword.get(opts, :live?, false)
    }
  end

  @doc "Distinct `handle_event/3` names among `events`, sorted."
  @spec event_names([PhoenixReplay.Recording.Event.t()]) :: [String.t()]
  def event_names(events) do
    names = for %{type: :event, data: %{name: name}} <- events, uniq: true, do: name
    Enum.sort(names)
  end
end
