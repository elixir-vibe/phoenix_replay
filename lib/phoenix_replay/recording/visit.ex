defmodule PhoenixReplay.Recording.Visit do
  @moduledoc """
  A visit, as the dashboard lists it: the recordings of one visit, with
  what describes it as a whole. See `PhoenixReplay.Plug` for what a visit
  is; a recording without one is a visit of its own.

    * `key` — the visit's id, or its only recording's id; see
      `PhoenixReplay.Recording.Summary.visit_key/1`
    * `recordings` — its recordings' summaries, in the order they started
    * `started_at` — when its first recording started, in Unix milliseconds
    * `duration_ms` — from its first recording's start to the last event of
      any of them
    * `url`, `source`, `medium`, `campaign`, `viewport`, `device`,
      `device_type`, `browser`, `release` and `tab` — those of its first
      recording, where the visit landed
    * `marks`, `error_count` and `event_count` — summed over its recordings
    * `live?` — whether any of its recordings is still running
  """

  alias PhoenixReplay.Recording.{Client, Summary}

  @type t :: %__MODULE__{
          key: String.t(),
          recordings: [Summary.t()],
          started_at: integer(),
          duration_ms: non_neg_integer(),
          url: String.t() | nil,
          source: String.t() | nil,
          medium: String.t() | nil,
          campaign: String.t() | nil,
          viewport: PhoenixReplay.Recording.viewport() | nil,
          device: String.t() | nil,
          device_type: Client.device_type() | nil,
          browser: String.t() | nil,
          release: String.t() | nil,
          tab: String.t() | nil,
          marks: %{String.t() => pos_integer()},
          error_count: non_neg_integer(),
          event_count: non_neg_integer(),
          live?: boolean()
        }

  @enforce_keys [:key, :recordings, :started_at]
  defstruct [
    :key,
    :recordings,
    :started_at,
    :url,
    :source,
    :medium,
    :campaign,
    :viewport,
    :device,
    :device_type,
    :browser,
    :release,
    :tab,
    duration_ms: 0,
    marks: %{},
    error_count: 0,
    event_count: 0,
    live?: false
  ]

  # What the visit takes from the recording it landed with.
  @landed [
    :url,
    :source,
    :medium,
    :campaign,
    :viewport,
    :device,
    :device_type,
    :browser,
    :release,
    :tab
  ]

  @doc """
  Groups summaries into visits, the most recently started first; see
  `PhoenixReplay.Recording.Summary.sort/1` for how ties are ordered.
  """
  @spec group([Summary.t()]) :: [t()]
  def group(summaries) do
    summaries
    |> Enum.group_by(&Summary.visit_key/1)
    |> Enum.map(fn {key, recordings} -> new(key, recordings) end)
    |> sort()
  end

  @doc "Orders visits most recently started first, ties by key."
  @spec sort([t()]) :: [t()]
  def sort(visits), do: Enum.sort_by(visits, &{&1.started_at, &1.key}, :desc)

  @doc "The visit made of `recordings`, all of visit `key`."
  @spec new(String.t(), [Summary.t()]) :: t()
  def new(key, recordings) do
    [first | _rest] = recordings = Enum.sort_by(recordings, &{&1.connected_at, &1.id})

    %__MODULE__{
      key: key,
      recordings: recordings,
      started_at: first.connected_at,
      duration_ms:
        Enum.max(Enum.map(recordings, &(&1.connected_at + &1.duration_ms))) - first.connected_at,
      marks: Enum.reduce(recordings, %{}, &Map.merge(&2, &1.marks, fn _name, a, b -> a + b end)),
      error_count: Enum.sum_by(recordings, & &1.error_count),
      event_count: Enum.sum_by(recordings, & &1.event_count),
      live?: Enum.any?(recordings, & &1.live?)
    }
    |> struct!(Map.take(first, @landed))
  end

  @doc "The recording of the visit with `id`, or `nil`."
  @spec recording(t(), String.t()) :: Summary.t() | nil
  def recording(%__MODULE__{recordings: recordings}, id),
    do: Enum.find(recordings, &(&1.id == id))
end
