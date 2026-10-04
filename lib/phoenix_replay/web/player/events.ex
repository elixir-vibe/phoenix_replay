defmodule PhoenixReplay.Web.Player.Events do
  @moduledoc """
  How the player presents a recording's events: their labels, the kinds
  the event list filters by, and their timeline markers.
  """

  alias PhoenixReplay.Collector
  alias PhoenixReplay.Recording
  alias PhoenixReplay.Recording.Event

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

  @doc "Classes for an event's timeline marker. Errors are larger and red."
  @spec marker_class(Event.t()) :: String.t()
  def marker_class(%Event{} = event) do
    if Event.error?(event), do: "size-2 bg-error", else: type_marker_class(event.type)
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
  defp type_marker_class(:exit), do: "size-2 bg-error"
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
