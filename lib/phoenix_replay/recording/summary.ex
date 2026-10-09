defmodule PhoenixReplay.Recording.Summary do
  @moduledoc """
  Lightweight description of a recording, used for listings and filtering.

  Storage backends return summaries without decoding full recordings.
  `event_names` are the distinct `handle_event/3` names, sorted, and
  `marks` the moments the session reached, by name, with how many times;
  see `PhoenixReplay.Recording.Event.mark_name/1`.
  `error_count` counts the events for which `PhoenixReplay.Recording.Event.error?/1`
  holds. `tab` is the browser tab the session ran in, when the client sent
  it, and `visit` the visit it belongs to, when `PhoenixReplay.Plug` kept
  one; see `visit_key/1`. `viewport`, `device`,
  `device_type` and `browser` describe the browser, and `source`, `medium`
  and `campaign` where the visit came from, as
  `PhoenixReplay.Recording.Client` names them. `saved_at` is when storage
  saved the recording, in Unix milliseconds, or `nil` before it is saved and
  for recordings saved before PhoenixReplay 0.5. `live?` is true while the
  recorded LiveView process is still running.
  """

  alias PhoenixReplay.Recording
  alias PhoenixReplay.Recording.{Client, Event, Traffic}

  @type t :: %__MODULE__{
          id: Recording.id(),
          view: String.t(),
          url: String.t() | nil,
          connected_at: integer(),
          event_count: non_neg_integer(),
          event_names: [String.t()],
          marks: %{String.t() => pos_integer()},
          error_count: non_neg_integer(),
          tab: String.t() | nil,
          visit: String.t() | nil,
          viewport: Recording.viewport() | nil,
          device: String.t() | nil,
          device_type: Client.device_type() | nil,
          browser: String.t() | nil,
          release: String.t() | nil,
          source: String.t() | nil,
          medium: String.t() | nil,
          campaign: String.t() | nil,
          duration_ms: non_neg_integer(),
          saved_at: integer() | nil,
          live?: boolean()
        }

  @typedoc "What a summary counts of a recording's events; see `totals/2`."
  @type totals :: %{
          event_count: non_neg_integer(),
          error_count: non_neg_integer(),
          event_names: [String.t()],
          marks: %{String.t() => pos_integer()},
          duration_ms: non_neg_integer()
        }

  @no_totals %{event_count: 0, error_count: 0, event_names: [], marks: %{}, duration_ms: 0}

  @enforce_keys [:id, :view, :connected_at]
  defstruct [
    :id,
    :view,
    :url,
    :connected_at,
    event_count: 0,
    event_names: [],
    marks: %{},
    error_count: 0,
    tab: nil,
    visit: nil,
    viewport: nil,
    device: nil,
    device_type: nil,
    browser: nil,
    release: nil,
    source: nil,
    medium: nil,
    campaign: nil,
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
      visit: recording.client.visit,
      viewport: recording.client.viewport,
      device: Client.device(recording.client.user_agent),
      device_type: Client.device_type(recording.client.viewport),
      browser: Client.browser_family(recording.client.user_agent),
      release: recording.code && recording.code.release,
      saved_at: Keyword.get(opts, :saved_at),
      live?: Keyword.get(opts, :live?, false)
    }

    summary
    |> struct!(Map.from_struct(Client.traffic(recording.client)))
    |> struct!(totals(recording.events))
  end

  @doc """
  Brings a summary saved by an earlier version up to date. Before 0.6,
  `source` held the campaign as `"google / cpc / spring"`, now split into
  `source`, `medium` and `campaign`, and there was no `device_type`.
  The browser's family cannot be told from the `device` saved then, so
  `browser` stays `nil`.
  """
  @spec upgrade(t()) :: t()
  def upgrade(%__MODULE__{} = summary) do
    summary
    |> upgrade_source()
    |> then(&%{&1 | device_type: &1.device_type || Client.device_type(&1.viewport)})
  end

  defp upgrade_source(%__MODULE__{source: source, medium: nil} = summary)
       when is_binary(source),
       do: struct!(summary, Map.from_struct(Traffic.from_legacy(source)))

  defp upgrade_source(summary), do: summary

  @doc """
  Counts `events` into `totals`, which start at zero: every event but
  pointer batches and client state, which are not shown as events; the events for which
  `PhoenixReplay.Recording.Event.error?/1` holds; the distinct
  `handle_event/3` names, sorted; the marks reached, by name, with how
  many times; and the time of the last event.

  A recording flushed to storage in chunks is counted chunk by chunk.
  """
  @spec totals([Event.t()], totals()) :: totals()
  def totals(events, totals \\ @no_totals) do
    {totals, names} = Enum.reduce(events, {totals, totals.event_names}, &count/2)
    %{totals | event_names: names |> Enum.uniq() |> Enum.sort()}
  end

  @doc "Adds one reaching of the mark `name` to `marks`, as `totals/2` counts them."
  @spec add_mark(%{String.t() => pos_integer()}, String.t() | nil) ::
          %{String.t() => pos_integer()}
  def add_mark(marks, nil), do: marks
  def add_mark(marks, name), do: Map.update(marks, name, 1, &(&1 + 1))

  @doc """
  How one event adds to `totals/2`: `1` or `0` to the event count and to
  the error count, its `handle_event/3` name, if it has one, and its name
  as a mark, if it is one.
  `PhoenixReplay.Session.Buffer` keeps running totals with it as events
  are written.
  """
  @spec counts(Event.t()) :: {0 | 1, 0 | 1, String.t() | nil, String.t() | nil}
  def counts(%Event{} = event) do
    {one(event.type not in [:pointer, :state]), one(Event.error?(event)), event_name(event),
     Event.mark_name(event)}
  end

  defp count(%Event{} = event, {totals, names}) do
    {shown, error, name, mark} = counts(event)

    totals = %{
      totals
      | event_count: totals.event_count + shown,
        error_count: totals.error_count + error,
        marks: add_mark(totals.marks, mark),
        duration_ms: max(totals.duration_ms, event.at)
    }

    {totals, if(name, do: [name | names], else: names)}
  end

  defp one(true), do: 1
  defp one(false), do: 0

  defp event_name(%Event{type: :event, data: %{name: name}}), do: name

  defp event_name(_event), do: nil

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
  The visit a recording belongs to: its `visit`, or its own id for one
  without, made before visits were kept or without `PhoenixReplay.Plug`,
  which is a visit of its own.
  """
  @spec visit_key(t()) :: String.t()
  def visit_key(%__MODULE__{visit: nil, id: id}), do: id
  def visit_key(%__MODULE__{visit: visit}), do: visit

  @doc """
  Orders summaries most recent first. Sessions that started in the same
  millisecond are ordered by id, so pages never repeat or skip them.
  """
  @spec sort([t()]) :: [t()]
  def sort(summaries), do: Enum.sort_by(summaries, &{&1.connected_at, &1.id}, :desc)
end
