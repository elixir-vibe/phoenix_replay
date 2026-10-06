defmodule PhoenixReplay.Recording.Filter do
  @moduledoc """
  Criteria for narrowing a list of `PhoenixReplay.Recording.Summary` structs.

  Filters round-trip through URL query parameters, so a filtered dashboard
  view can be shared as a link:

    * `"q"` — text found in the recording's URL, id, event names, mark
      names, source or campaign
    * `"view"` — exact view module name, such as `"MyAppWeb.CheckoutLive"`
    * `"event"` — a `handle_event/3` name the session triggered
    * `"mark"` — the name of a moment the session reached; see
      `PhoenixReplay.Recording.Event.mark_name/1`
    * `"source"`, `"medium"` and `"campaign"` — where the visit came from,
      such as `"google"`, `"cpc"` and `"spring"`; see
      `PhoenixReplay.Recording.Client.traffic/1`
    * `"device_type"` — `"phone"`, `"tablet"` or `"desktop"`
    * `"browser"` — the browser's family, such as `"Mobile Safari"`
    * `"within"` — `"15m"`, `"1h"`, `"24h"`, `"7d"` or `"30d"` since the
      session started
    * `"from"` and `"to"` — the session started within this time range,
      each an ISO 8601 time such as `"2026-10-06T14:00:00Z"`
    * `"longer_than"` — a minimum duration, in seconds
    * `"min_events"` — minimum number of recorded events
    * `"errors"` — `"1"` to keep only sessions with an error, such as an
      error log, a failed query or a crash
    * `"tab"` — sessions from one browser tab, a user's journey

  Blank or invalid parameters are ignored.
  """

  alias PhoenixReplay.Recording.{Client, Summary}

  @windows %{
    "15m" => :timer.minutes(15),
    "1h" => :timer.hours(1),
    "24h" => :timer.hours(24),
    "7d" => :timer.hours(24 * 7),
    "30d" => :timer.hours(24 * 30)
  }

  @type t :: %__MODULE__{
          query: String.t() | nil,
          view: String.t() | nil,
          event: String.t() | nil,
          mark: String.t() | nil,
          source: String.t() | nil,
          medium: String.t() | nil,
          campaign: String.t() | nil,
          device_type: Client.device_type() | nil,
          browser: String.t() | nil,
          within: String.t() | nil,
          from: integer() | nil,
          to: integer() | nil,
          longer_than: pos_integer() | nil,
          min_events: pos_integer() | nil,
          errors: boolean(),
          tab: String.t() | nil
        }

  defstruct [
    :query,
    :view,
    :event,
    :mark,
    :source,
    :medium,
    :campaign,
    :device_type,
    :browser,
    :within,
    :from,
    :to,
    :longer_than,
    :min_events,
    :tab,
    errors: false
  ]

  # Criteria that match one of a summary's values exactly.
  @exact [:view, :source, :medium, :campaign, :device_type, :browser]

  @doc "The supported `\"within\"` values, shortest first."
  @spec windows() :: [String.t()]
  def windows, do: ~w(15m 1h 24h 7d 30d)

  @doc "Builds a filter from string-keyed query parameters."
  @spec from_params(map()) :: t()
  def from_params(params) when is_map(params) do
    %__MODULE__{
      query: text(params["q"]),
      view: text(params["view"]),
      event: text(params["event"]),
      mark: text(params["mark"]),
      source: text(params["source"]),
      medium: text(params["medium"]),
      campaign: text(params["campaign"]),
      device_type: if(params["device_type"] in Client.device_types(), do: params["device_type"]),
      browser: text(params["browser"]),
      within: if(Map.has_key?(@windows, params["within"]), do: params["within"]),
      from: time(params["from"]),
      to: time(params["to"]),
      longer_than: positive_integer(params["longer_than"]),
      min_events: positive_integer(params["min_events"]),
      errors: params["errors"] == "1",
      tab: text(params["tab"])
    }
  end

  @doc "Converts a filter back to query parameters, omitting unset criteria."
  @spec to_params(t()) :: %{optional(String.t()) => String.t()}
  def to_params(%__MODULE__{} = filter) do
    [
      {"q", filter.query},
      {"view", filter.view},
      {"event", filter.event},
      {"mark", filter.mark},
      {"source", filter.source},
      {"medium", filter.medium},
      {"campaign", filter.campaign},
      {"device_type", filter.device_type},
      {"browser", filter.browser},
      {"within", filter.within},
      {"from", filter.from && iso8601(filter.from)},
      {"to", filter.to && iso8601(filter.to)},
      {"longer_than", filter.longer_than && Integer.to_string(filter.longer_than)},
      {"min_events", filter.min_events && Integer.to_string(filter.min_events)},
      {"errors", if(filter.errors, do: "1")},
      {"tab", filter.tab}
    ]
    |> Enum.reject(fn {_key, value} -> is_nil(value) end)
    |> Map.new()
  end

  @typedoc """
  A criterion whose values can be listed and counted, for suggesting them:
  see `values_of/2`.
  """
  @type field ::
          :view | :event | :mark | :source | :medium | :campaign | :device_type | :browser

  @fields [:view, :event, :mark, :source, :medium, :campaign, :device_type, :browser]

  @doc "The criteria whose values can be listed; see `t:field/0`."
  @spec fields() :: [field()]
  def fields, do: @fields

  @doc "The values a summary has for `field`, such as its view or its event names."
  @spec values_of(Summary.t(), field()) :: [String.t()]
  def values_of(%Summary{event_names: names}, :event), do: names
  def values_of(%Summary{marks: marks}, :mark), do: Map.keys(marks)

  def values_of(%Summary{} = summary, field) when field in @exact,
    do: summary |> Map.fetch!(field) |> List.wrap()

  @doc """
  Counts the values of `field` among the `summaries` matching `filter`,
  ignoring the filter's own criterion on `field`, so the other values
  stay on offer: the most common first, at most `limit`. `now` is in Unix
  milliseconds, for `"within"`.
  """
  @spec count_values([Summary.t()], field(), t(), integer(), pos_integer()) ::
          [{String.t(), pos_integer()}]
  def count_values(summaries, field, %__MODULE__{} = filter, now, limit) do
    summaries
    |> select(Map.put(filter, field, nil), now)
    |> Enum.flat_map(&values_of(&1, field))
    |> Enum.frequencies()
    |> top(limit)
  end

  @doc "The most common of counted values, then by value, at most `limit`."
  @spec top(%{String.t() => pos_integer()} | [{String.t(), pos_integer()}], pos_integer()) ::
          [{String.t(), pos_integer()}]
  def top(counts, limit),
    do: counts |> Enum.sort_by(fn {value, count} -> {-count, value} end) |> Enum.take(limit)

  @typedoc "Sessions started in one stretch of time: its start, how many, and how many with an error."
  @type bucket :: {integer(), pos_integer(), non_neg_integer()}

  # The stretch of time a chart of start times covers without a range.
  @default_span :timer.hours(24 * 30)

  @doc """
  The stretch of time `filter` covers at `now`, in Unix milliseconds: its
  window, its range, completed by the last 30 days or now where it is
  open, or the last 30 days without either.
  """
  @spec time_range(t(), integer()) :: {integer(), integer()}
  def time_range(%__MODULE__{within: within}, now) when is_binary(within),
    do: {now - @windows[within], now}

  def time_range(%__MODULE__{from: from, to: to}, now) do
    to = to || now
    {from || to - @default_span, to}
  end

  @doc """
  Counts the `summaries` matching `filter` by when they started, in
  stretches of `size` milliseconds from the Unix epoch, earliest first;
  see `t:bucket/0`.
  """
  @spec histogram([Summary.t()], t(), pos_integer(), integer()) :: [bucket()]
  def histogram(summaries, %__MODULE__{} = filter, size, now) do
    summaries
    |> select(filter, now)
    |> Enum.group_by(&bucket(&1.connected_at, size))
    |> Enum.map(fn {start, started} ->
      {start, length(started), Enum.count(started, &(&1.error_count > 0))}
    end)
    |> Enum.sort()
  end

  @doc "The start of the stretch of `size` milliseconds that `at` falls in."
  @spec bucket(integer(), pos_integer()) :: integer()
  def bucket(at, size), do: at - rem(at, size)

  @doc "Returns true when no criteria are set."
  @spec empty?(t()) :: boolean()
  def empty?(%__MODULE__{} = filter), do: to_params(filter) == %{}

  @doc "Keeps the summaries matching every criterion. `now` is in Unix milliseconds."
  @spec select([Summary.t()], t(), integer()) :: [Summary.t()]
  def select(summaries, %__MODULE__{} = filter, now) do
    Enum.filter(summaries, &matches?(&1, filter, now))
  end

  @typedoc """
  Which page of matching summaries to read:

    * `:now` — the current time in Unix milliseconds, for `"within"`
    * `:until` — only recordings saved at or before this time, so pages stay
      put while sessions end; see `PhoenixReplay.Recording.Summary.stored_at/1`
    * `:since` — only recordings saved after this time
    * `:offset` and `:limit` — the slice to return
  """
  @type page_opts :: [
          now: integer(),
          until: integer() | nil,
          since: integer() | nil,
          offset: non_neg_integer(),
          limit: non_neg_integer()
        ]

  @doc """
  Reads a page of `summaries`, which are ordered most recent first, and
  counts every summary that matches. See `t:page_opts/0`.
  """
  @spec page([Summary.t()], t(), page_opts()) :: {[Summary.t()], non_neg_integer()}
  def page(summaries, %__MODULE__{} = filter, opts) do
    {until, since} = {opts[:until], opts[:since]}

    matching =
      summaries
      |> select(filter, Keyword.fetch!(opts, :now))
      |> Enum.filter(fn summary ->
        (is_nil(until) or Summary.stored_at(summary) <= until) and
          (is_nil(since) or Summary.stored_at(summary) > since)
      end)

    {Enum.slice(matching, Keyword.get(opts, :offset, 0), Keyword.fetch!(opts, :limit)),
     length(matching)}
  end

  @doc """
  The earliest start time `"within"` allows at `now`, in Unix milliseconds,
  or `nil` without it.
  """
  @spec started_after(t(), integer()) :: integer() | nil
  def started_after(%__MODULE__{within: nil}, _now), do: nil
  def started_after(%__MODULE__{within: within}, now), do: now - @windows[within]

  defp matches?(summary, filter, now) do
    query?(summary, filter.query) and Enum.all?(@exact, &exact?(summary, filter, &1)) and
      (is_nil(filter.event) or filter.event in summary.event_names) and
      (is_nil(filter.mark) or Map.has_key?(summary.marks, filter.mark)) and
      (is_nil(filter.longer_than) or summary.duration_ms >= filter.longer_than * 1_000) and
      (is_nil(filter.within) or summary.connected_at >= started_after(filter, now)) and
      (is_nil(filter.from) or summary.connected_at >= filter.from) and
      (is_nil(filter.to) or summary.connected_at <= filter.to) and
      (is_nil(filter.min_events) or summary.event_count >= filter.min_events) and
      (not filter.errors or summary.error_count > 0) and
      (is_nil(filter.tab) or summary.tab == filter.tab)
  end

  defp exact?(summary, filter, criterion) do
    case Map.fetch!(filter, criterion) do
      nil -> true
      value -> Map.fetch!(summary, criterion) == value
    end
  end

  defp query?(_summary, nil), do: true

  defp query?(summary, query) do
    query = String.downcase(query)

    [summary.id, summary.url, summary.source, summary.campaign]
    |> Enum.concat(summary.event_names)
    |> Enum.concat(Map.keys(summary.marks))
    |> Enum.any?(&(is_binary(&1) and &1 |> String.downcase() |> String.contains?(query)))
  end

  # Unix milliseconds of an ISO 8601 time with an offset.
  defp time(value) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, time, _offset} -> DateTime.to_unix(time, :millisecond)
      {:error, _reason} -> nil
    end
  end

  defp time(_value), do: nil

  defp iso8601(unix_ms),
    do:
      unix_ms
      |> DateTime.from_unix!(:millisecond)
      |> DateTime.truncate(:second)
      |> DateTime.to_iso8601()

  defp text(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp text(_value), do: nil

  defp positive_integer(value) when is_binary(value) do
    case Integer.parse(value) do
      {integer, ""} when integer > 0 -> integer
      _invalid -> nil
    end
  end

  defp positive_integer(_value), do: nil
end
