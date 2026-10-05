defmodule PhoenixReplay.Recordings.Filter do
  @moduledoc """
  Criteria for narrowing a list of `PhoenixReplay.Recording.Summary` structs.

  Filters round-trip through URL query parameters, so a filtered dashboard
  view can be shared as a link:

    * `"q"` — text found in the recording's URL, id or event names
    * `"view"` — exact view module name, such as `"MyAppWeb.CheckoutLive"`
    * `"event"` — a `handle_event/3` name the session triggered
    * `"within"` — `"1h"`, `"24h"` or `"7d"` since the session started
    * `"min_events"` — minimum number of recorded events
    * `"errors"` — `"1"` to keep only sessions with an error, such as an
      error log, a failed query or a crash
    * `"tab"` — sessions from one browser tab, a user's journey

  Blank or invalid parameters are ignored.
  """

  alias PhoenixReplay.Recording.Summary

  @windows %{"1h" => :timer.hours(1), "24h" => :timer.hours(24), "7d" => :timer.hours(24 * 7)}

  @type t :: %__MODULE__{
          query: String.t() | nil,
          view: String.t() | nil,
          event: String.t() | nil,
          within: String.t() | nil,
          min_events: pos_integer() | nil,
          errors: boolean(),
          tab: String.t() | nil
        }

  defstruct [:query, :view, :event, :within, :min_events, :tab, errors: false]

  @doc "The supported `\"within\"` values, shortest first."
  @spec windows() :: [String.t()]
  def windows, do: ~w(1h 24h 7d)

  @doc "Builds a filter from string-keyed query parameters."
  @spec from_params(map()) :: t()
  def from_params(params) when is_map(params) do
    %__MODULE__{
      query: text(params["q"]),
      view: text(params["view"]),
      event: text(params["event"]),
      within: if(Map.has_key?(@windows, params["within"]), do: params["within"]),
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
      {"within", filter.within},
      {"min_events", filter.min_events && Integer.to_string(filter.min_events)},
      {"errors", if(filter.errors, do: "1")},
      {"tab", filter.tab}
    ]
    |> Enum.reject(fn {_key, value} -> is_nil(value) end)
    |> Map.new()
  end

  @doc "Returns true when no criteria are set."
  @spec empty?(t()) :: boolean()
  def empty?(%__MODULE__{} = filter), do: to_params(filter) == %{}

  @doc "Keeps the summaries matching every criterion. `now` is in Unix milliseconds."
  @spec apply([Summary.t()], t(), integer()) :: [Summary.t()]
  def apply(summaries, %__MODULE__{} = filter, now) do
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
      |> __MODULE__.apply(filter, Keyword.fetch!(opts, :now))
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
    query?(summary, filter.query) and
      (is_nil(filter.view) or summary.view == filter.view) and
      (is_nil(filter.event) or filter.event in summary.event_names) and
      (is_nil(filter.within) or summary.connected_at >= started_after(filter, now)) and
      (is_nil(filter.min_events) or summary.event_count >= filter.min_events) and
      (not filter.errors or summary.error_count > 0) and
      (is_nil(filter.tab) or summary.tab == filter.tab)
  end

  defp query?(_summary, nil), do: true

  defp query?(summary, query) do
    query = String.downcase(query)

    Enum.any?(
      [summary.id, summary.url || "" | summary.event_names],
      &(&1 |> String.downcase() |> String.contains?(query))
    )
  end

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
