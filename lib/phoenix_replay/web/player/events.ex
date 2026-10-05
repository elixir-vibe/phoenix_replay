defmodule PhoenixReplay.Web.Player.Events do
  @moduledoc """
  How the player presents a recording's events: their labels, the kinds
  the event list filters by, and their timeline markers.
  """

  alias PhoenixReplay.Collector
  alias PhoenixReplay.Recording
  alias PhoenixReplay.Recording.Event
  alias PhoenixReplay.Web.Format

  @typedoc "What the event list filters by."
  @type kind :: String.t()

  @doc """
  The kind an event type is filtered as: `"liveview"`, `"telemetry"` or
  `"logs"`.
  """
  @spec kind(Event.type()) :: kind()
  def kind(:telemetry), do: "telemetry"
  def kind(:log), do: "logs"
  def kind(_type), do: "liveview"

  @doc "The kinds in a recording, LiveView first."
  @spec kinds(Recording.t()) :: [kind()]
  def kinds(%Recording{events: events}) do
    events
    |> Enum.map(&kind(&1.type))
    |> Enum.uniq()
    |> Enum.sort_by(&(&1 != "liveview"))
  end

  @typedoc "An event with its index in the recording."
  @type indexed :: {Event.t(), non_neg_integer()}

  # Events that start an interaction; the rest follow the one before them.
  @starts [:mount, :event, :params, :info]

  @doc """
  Groups events into interactions: a mount, user event, navigation or
  message, followed by the renders, component updates and collected events
  it caused.
  """
  @spec interactions([Event.t()]) :: [{indexed(), [indexed()]}]
  def interactions(events) do
    events
    |> Enum.with_index()
    |> Enum.chunk_while(nil, &interaction/2, &close_interaction/1)
  end

  defp interaction({%Event{type: type}, _index} = item, acc) when type in @starts do
    case acc do
      nil -> {:cont, {item, []}}
      acc -> {:cont, close(acc), {item, []}}
    end
  end

  defp interaction(item, nil), do: {:cont, {item, []}}
  defp interaction(item, {head, rows}), do: {:cont, {head, [item | rows]}}

  defp close_interaction(nil), do: {:cont, nil}
  defp close_interaction(acc), do: {:cont, close(acc), nil}

  defp close({head, rows}), do: {head, Enum.reverse(rows)}

  @doc "The events of each kind in a recording, as timeline lanes."
  @spec lanes(Recording.t()) :: [{kind(), [indexed()]}]
  def lanes(%Recording{events: events} = recording) do
    indexed = Enum.with_index(events)

    for kind <- kinds(recording),
        do: {kind, Enum.filter(indexed, &(kind(elem(&1, 0).type) == kind))}
  end

  @doc "How many events of each kind a recording has."
  @spec kind_counts(Recording.t()) :: %{kind() => non_neg_integer()}
  def kind_counts(%Recording{events: events}), do: Enum.frequencies_by(events, &kind(&1.type))

  @doc "The colour class of a kind's swatch."
  @spec kind_class(kind()) :: String.t()
  def kind_class("liveview"), do: "bg-kind-event"
  def kind_class("telemetry"), do: "bg-kind-query"
  def kind_class("logs"), do: "bg-kind-log"

  @doc "The index of the first event that reports an error, or `nil`."
  @spec first_error_index(Recording.t()) :: non_neg_integer() | nil
  def first_error_index(%Recording{events: events}), do: Enum.find_index(events, &Event.error?/1)

  @doc "The assigns an event set, which the state view marks as changed."
  @spec changed_keys(Event.t() | nil) :: [atom()]
  def changed_keys(%Event{type: type, data: %{assigns: assigns}}) when type in [:mount, :render],
    do: Map.keys(assigns)

  def changed_keys(_event), do: []

  @doc "Whether an event's label contains `query`, ignoring case."
  @spec matches?(Event.t(), String.t()) :: boolean()
  def matches?(_event, ""), do: true

  def matches?(event, query),
    do: event |> label() |> String.downcase() |> String.contains?(String.downcase(query))

  @doc """
  Name–value pairs describing a collected event or an exit, shown when it
  is selected. Other events describe themselves through the assigns.
  """
  @spec details(Event.t()) :: [{String.t(), String.t()}]
  def details(%Event{type: :telemetry, data: data} = event) do
    present([
      {"Event", Collector.name(data.event)},
      {"Summary", data.summary},
      {"Duration", event |> Event.duration() |> duration()},
      {"Error", data.error},
      {"Metadata", metadata(data.metadata)}
    ])
  end

  def details(%Event{type: :log, data: data}) do
    present([
      {"Level", to_string(data.level)},
      {"Message", data.message},
      {"Metadata", metadata(data.metadata)}
    ])
  end

  def details(%Event{type: :exit, data: %{reason: reason}}), do: [{"Reason", reason}]
  def details(%Event{}), do: []

  defp present(details), do: Enum.reject(details, fn {_name, value} -> value == nil end)

  defp duration(nil), do: nil
  defp duration(ms), do: Format.milliseconds(ms)

  defp metadata(metadata) when metadata == %{}, do: nil
  defp metadata(metadata), do: inspect(metadata, pretty: true, limit: 50)

  @doc "A kind's name in the filter."
  @spec kind_label(kind()) :: String.t()
  def kind_label("liveview"), do: "LiveView"
  def kind_label("telemetry"), do: "Telemetry"
  def kind_label("logs"), do: "Logs"

  @doc """
  Whether an event was collected from telemetry or logs. Collected events
  follow the LiveView event that caused them.
  """
  @spec collected?(Event.t()) :: boolean()
  def collected?(%Event{type: type}), do: type in [:telemetry, :log]

  @doc "The number of events that report an error."
  @spec error_count(Recording.t()) :: non_neg_integer()
  def error_count(%Recording{events: events}), do: Enum.count(events, &Event.error?/1)

  @doc "The number of collected events dropped over their limits."
  @spec dropped_count(Recording.t()) :: non_neg_integer()
  def dropped_count(%Recording{dropped: dropped}),
    do: Enum.sum_by(dropped, fn {_name, count} -> count end)

  # Errors stand out: larger, red, with a soft ring.
  @error_marker "size-2.5 bg-error ring-3 ring-error-soft"

  @doc "Classes for an event's timeline marker. Errors are larger and red."
  @spec marker_class(Event.t()) :: String.t()
  def marker_class(%Event{} = event) do
    if Event.error?(event), do: @error_marker, else: type_marker_class(event.type)
  end

  defp type_marker_class(:mount), do: "size-1.5 bg-ink"
  defp type_marker_class(:event), do: "size-1.5 bg-kind-event"
  defp type_marker_class(:params), do: "size-1.5 bg-kind-nav"
  defp type_marker_class(:info), do: "size-1 bg-kind-log"
  defp type_marker_class(:render), do: "size-1 bg-kind-render"
  defp type_marker_class(:component), do: "size-1 bg-kind-component"
  defp type_marker_class(:component_destroyed), do: "size-1 bg-kind-component"
  defp type_marker_class(:telemetry), do: "size-1 bg-kind-query"
  defp type_marker_class(:log), do: "size-1 bg-kind-log"
  defp type_marker_class(:exit), do: @error_marker
  defp type_marker_class(:viewport), do: "size-1 bg-kind-render"

  @doc "One-line description of an event."
  @spec label(Event.t()) :: String.t()
  def label(%Event{type: :mount}), do: "mount"
  def label(%Event{type: :params, data: %{uri: uri}}), do: "navigate → #{uri}"
  def label(%Event{type: :info, data: %{tag: nil}}), do: "handle_info"
  def label(%Event{type: :info, data: %{tag: tag}}), do: "handle_info #{inspect(tag)}"
  def label(%Event{type: :render, data: %{assigns: assigns}}), do: assigns_label(assigns)

  def label(%Event{type: :component, data: %{module: module, id: id, assigns: assigns}}),
    do: "#{component_label(module, id)} #{assigns_label(assigns)}"

  def label(%Event{type: :component_destroyed, data: %{module: module, id: id}}),
    do: "#{component_label(module, id)} removed"

  def label(%Event{type: :telemetry, data: %{event: event} = data}) do
    label = data.summary || Collector.name(event)
    if data.error, do: "#{label} — #{data.error}", else: label
  end

  def label(%Event{type: :log, data: %{level: level, message: message}}),
    do: "[#{level}] #{message}"

  def label(%Event{type: :viewport, data: %{width: width, height: height}}),
    do: "viewport #{width} × #{height}"

  def label(%Event{type: :exit, data: %{reason: reason}}),
    do: "exited: " <> (reason |> String.split("\n", parts: 2) |> hd())

  def label(%Event{type: :event, data: %{name: name, params: params} = data}) do
    name =
      case data do
        %{target: {module, id}} -> "#{name} → #{component_label(module, id)}"
        %{} -> name
      end

    case params_label(params) do
      "" -> name
      label -> "#{name}: #{label}"
    end
  end

  defp component_label(module, id) when is_binary(id), do: "#{inspect(module)}##{id}"
  defp component_label(module, id), do: "#{inspect(module)}##{inspect(id)}"

  defp assigns_label(assigns) do
    "assigns " <> (assigns |> Map.keys() |> Enum.sort() |> Enum.map_join(", ", &to_string/1))
  end

  defp params_label(params) do
    params
    |> Enum.reject(fn {key, _value} -> String.starts_with?(key, "_") end)
    |> Enum.flat_map(&flatten_param/1)
    |> Enum.map_join(", ", fn {key, value} -> "#{key}=#{String.slice(value, 0, 40)}" end)
  end

  defp flatten_param({_key, %{} = nested}), do: Enum.flat_map(nested, &flatten_param/1)
  defp flatten_param({key, value}) when is_binary(value) and value != "", do: [{key, value}]
  defp flatten_param(_param), do: []
end
