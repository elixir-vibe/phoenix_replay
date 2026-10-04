defmodule PhoenixReplay.Web.Components do
  @moduledoc """
  Function components and formatting shared by the dashboard views.
  """

  use Phoenix.Component

  alias PhoenixReplay.Collector
  alias PhoenixReplay.Recording.Event

  @doc "A small bordered button."
  attr :variant, :string, values: ~w(default danger), default: "default"
  attr :rest, :global, include: ~w(disabled)
  slot :inner_block, required: true

  @spec button(map()) :: Phoenix.LiveView.Rendered.t()
  def button(assigns) do
    ~H"""
    <button
      type="button"
      class={[
        "rounded-md border px-2.5 py-1 text-xs transition-colors",
        "focus-visible:outline-2 focus-visible:outline-offset-1 focus-visible:outline-indigo-500",
        "disabled:cursor-default disabled:opacity-30",
        @variant == "default" && "border-neutral-200 bg-white text-neutral-700 hover:bg-neutral-50",
        @variant == "danger" && "border-red-200 bg-white text-red-700 hover:bg-red-50"
      ]}
      {@rest}
    >
      {render_slot(@inner_block)}
    </button>
    """
  end

  @doc "Shows the `:error` flash, if any."
  attr :flash, :map, required: true

  @spec flash_error(map()) :: Phoenix.LiveView.Rendered.t()
  def flash_error(assigns) do
    ~H"""
    <p
      :if={message = Phoenix.Flash.get(@flash, :error)}
      role="alert"
      class="mb-4 rounded-md border border-red-200 bg-red-50 px-4 py-2 text-sm text-red-800"
    >
      {message}
    </p>
    """
  end

  @doc "Badge marking a recording whose LiveView is still running."
  @spec live_badge(map()) :: Phoenix.LiveView.Rendered.t()
  def live_badge(assigns) do
    ~H"""
    <span class="inline-flex items-center gap-1 rounded-full bg-green-100 px-2 py-0.5 text-xs font-semibold text-green-800">
      <span class="size-2 animate-pulse rounded-full bg-green-500"></span> LIVE
    </span>
    """
  end

  @doc "Formats an offset as `m:ss`."
  @spec clock(non_neg_integer()) :: String.t()
  def clock(ms) do
    seconds = div(ms, 1000)

    "#{div(seconds, 60)}:#{seconds |> rem(60) |> Integer.to_string() |> String.pad_leading(2, "0")}"
  end

  @doc "Formats a duration as `12s` or `3m 4s`."
  @spec duration(non_neg_integer()) :: String.t()
  def duration(ms) do
    seconds = div(ms, 1000)

    case div(seconds, 60) do
      0 -> "#{seconds}s"
      minutes -> "#{minutes}m #{rem(seconds, 60)}s"
    end
  end

  @doc "Formats a Unix millisecond timestamp as UTC `YYYY-MM-DD HH:MM:SS`."
  @spec timestamp(integer()) :: String.t()
  def timestamp(unix_ms) do
    unix_ms |> DateTime.from_unix!(:millisecond) |> Calendar.strftime("%Y-%m-%d %H:%M:%S")
  end

  @doc """
  Parses a non-negative integer parameter, falling back to `default`.

  Accepts strings from `phx-value-*` attributes and integers from hook payloads.
  """
  @spec parse_integer(term(), integer()) :: integer()
  def parse_integer(value, _default) when is_integer(value) and value >= 0, do: value

  def parse_integer(value, default) when is_binary(value) do
    case Integer.parse(value) do
      {integer, ""} when integer >= 0 -> integer
      _invalid -> default
    end
  end

  def parse_integer(_value, default), do: default

  @doc "Icon for an event type."
  @spec event_icon(Event.type()) :: String.t()
  def event_icon(:mount), do: "🚀"
  def event_icon(:event), do: "⚡"
  def event_icon(:params), do: "🔗"
  def event_icon(:info), do: "📨"
  def event_icon(:render), do: "📝"
  def event_icon(:component), do: "🧩"
  def event_icon(:component_destroyed), do: "🧩"
  def event_icon(:telemetry), do: "⏱"
  def event_icon(:log), do: "💬"
  def event_icon(:exit), do: "💥"
  def event_icon(:viewport), do: "📐"

  @doc """
  Groups event types for filtering the event list: `"liveview"`,
  `"telemetry"` or `"logs"`.
  """
  @spec event_kind(Event.type()) :: String.t()
  def event_kind(:telemetry), do: "telemetry"
  def event_kind(:log), do: "logs"
  def event_kind(_type), do: "liveview"

  @doc "Tailwind classes for an event's timeline marker. Errors stand out in red."
  @spec marker_class(Event.t()) :: String.t()
  def marker_class(%Event{} = event) do
    if Event.error?(event), do: "size-2 bg-red-600", else: type_marker_class(event.type)
  end

  defp type_marker_class(:mount), do: "size-1.5 bg-indigo-600"
  defp type_marker_class(:event), do: "size-1.5 bg-amber-500"
  defp type_marker_class(:params), do: "size-1.5 bg-sky-500"
  defp type_marker_class(:info), do: "size-1 bg-neutral-500"
  defp type_marker_class(:render), do: "size-1 bg-neutral-400"
  defp type_marker_class(:component), do: "size-1 bg-violet-400"
  defp type_marker_class(:component_destroyed), do: "size-1 bg-violet-400"
  defp type_marker_class(:telemetry), do: "size-1 bg-teal-500"
  defp type_marker_class(:log), do: "size-1 bg-neutral-300"
  defp type_marker_class(:exit), do: "size-2 bg-red-600"
  defp type_marker_class(:viewport), do: "size-1 bg-neutral-500"

  @doc "Describes a viewport as `390 × 844 @3x`."
  @spec viewport_label(PhoenixReplay.Recording.viewport()) :: String.t()
  def viewport_label(%{width: width, height: height, dpr: dpr}) do
    density = if dpr == 1, do: "", else: " @#{format_dpr(dpr)}x"
    "#{width} × #{height}#{density}"
  end

  defp format_dpr(dpr) when is_integer(dpr), do: Integer.to_string(dpr)
  defp format_dpr(dpr) when dpr == trunc(dpr), do: dpr |> trunc() |> Integer.to_string()
  defp format_dpr(dpr), do: :erlang.float_to_binary(dpr / 1, decimals: 1)

  @browsers [
    {"Edg/", "Edge"},
    {"Firefox/", "Firefox"},
    {"Chrome/", "Chrome"},
    {"Safari/", "Safari"}
  ]
  @systems [
    {"iPhone", "iOS"},
    {"iPad", "iPadOS"},
    {"Android", "Android"},
    {"Mac OS X", "macOS"},
    {"Windows", "Windows"},
    {"Linux", "Linux"}
  ]

  @doc """
  Names the browser and system in a user agent, such as `"Safari on iOS"`,
  or returns `nil` when neither is recognized.
  """
  @spec device_label(String.t() | nil) :: String.t() | nil
  def device_label(nil), do: nil

  def device_label(user_agent) do
    case Enum.reject([known(user_agent, @browsers), known(user_agent, @systems)], &is_nil/1) do
      [] -> nil
      parts -> Enum.join(parts, " on ")
    end
  end

  defp known(user_agent, names) do
    Enum.find_value(names, fn {marker, name} ->
      if String.contains?(user_agent, marker), do: name
    end)
  end

  @doc "The path and query of a URL, for showing where a user came from."
  @spec path_of(String.t()) :: String.t()
  def path_of(url) do
    case URI.parse(url) do
      %URI{path: path, query: nil} when is_binary(path) -> path
      %URI{path: path, query: query} when is_binary(path) -> path <> "?" <> query
      _other -> url
    end
  end

  @doc "Formats a duration in milliseconds as `0.42 ms`, `12 ms` or `1.5 s`."
  @spec milliseconds(number()) :: String.t()
  def milliseconds(ms) when ms < 10, do: "#{:erlang.float_to_binary(ms / 1, decimals: 2)} ms"
  def milliseconds(ms) when ms < 1_000, do: "#{round(ms)} ms"
  def milliseconds(ms), do: "#{:erlang.float_to_binary(ms / 1_000, decimals: 1)} s"

  @doc "One-line description of an event."
  @spec event_label(Event.t()) :: String.t()
  def event_label(%Event{type: :mount}), do: "mount"
  def event_label(%Event{type: :params, data: %{uri: uri}}), do: "navigate → #{uri}"
  def event_label(%Event{type: :info, data: %{tag: nil}}), do: "handle_info"
  def event_label(%Event{type: :info, data: %{tag: tag}}), do: "handle_info #{inspect(tag)}"
  def event_label(%Event{type: :render, data: %{assigns: assigns}}), do: assigns_label(assigns)

  def event_label(%Event{type: :component, data: %{module: module, id: id, assigns: assigns}}),
    do: "#{component_label(module, id)} #{assigns_label(assigns)}"

  def event_label(%Event{type: :component_destroyed, data: %{module: module, id: id}}),
    do: "#{component_label(module, id)} removed"

  def event_label(%Event{type: :telemetry, data: %{event: event} = data}) do
    label = data.summary || Collector.name(event)
    if data.error, do: "#{label} — #{data.error}", else: label
  end

  def event_label(%Event{type: :log, data: %{level: level, message: message}}),
    do: "[#{level}] #{message}"

  def event_label(%Event{type: :viewport, data: %{width: width, height: height}}),
    do: "viewport #{width} × #{height}"

  def event_label(%Event{type: :exit, data: %{reason: reason}}),
    do: "exited: " <> (reason |> String.split("\n", parts: 2) |> hd())

  def event_label(%Event{type: :event, data: %{name: name, params: params} = data}) do
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
