defmodule PhoenixReplay.Recording.Event do
  @moduledoc """
  A single entry in a recording's timeline.

  `at` is the offset in milliseconds from the moment recording started.
  The shape of `data` depends on `type`:

    * `:mount` — `%{assigns: map}`, the assigns when recording started
    * `:event` — `%{name: String.t(), params: map}`, a `handle_event/3` call;
      events handled by a LiveComponent also carry `target: {module, id}`
    * `:params` — `%{params: map, uri: String.t()}`, a `handle_params/3` call
    * `:info` — `%{tag: atom | nil}`, a `handle_info/2` call; only the message
      tag is kept so arbitrary message contents are never stored
    * `:render` — `%{assigns: map}`, the assigns changed by a render
    * `:component` — `%{module: module, id: term, assigns: map}`, the
      assigns of a LiveComponent changed by an update or event
    * `:component_destroyed` — `%{module: module, id: term}`, a
      LiveComponent removed from the page
    * `:telemetry` — `%{event: [atom], summary: String.t() | nil,
      measurements: map, metadata: map, error: String.t() | nil}`, a
      telemetry event captured by a `PhoenixReplay.Collector`
    * `:log` — `%{level: Logger.level(), message: String.t(), metadata: map}`,
      a log message, see `PhoenixReplay.Capture.Logs`
    * `:exit` — `%{reason: String.t()}`, the LiveView process exited
      abnormally
    * `:viewport` — `%{width: integer, height: integer, dpr: number}`, the
      browser's viewport changed, as seen with the user's next interaction

  `:telemetry`, `:log` and `:exit` events describe what happened around
  the view; they do not change the replayed state.
  """

  @type type ::
          :mount
          | :event
          | :params
          | :info
          | :render
          | :component
          | :component_destroyed
          | :telemetry
          | :log
          | :exit
          | :viewport

  @type t :: %__MODULE__{at: non_neg_integer(), type: type(), data: map()}

  @enforce_keys [:at, :type]
  defstruct [:at, :type, data: %{}]

  @error_levels [:error, :critical, :alert, :emergency]

  @doc "Returns true for an exit, an error log, or a telemetry event that captured an error."
  @spec error?(t()) :: boolean()
  def error?(%__MODULE__{type: :exit}), do: true
  def error?(%__MODULE__{type: :log, data: %{level: level}}), do: level in @error_levels
  def error?(%__MODULE__{type: :telemetry, data: %{error: error}}), do: error != nil
  def error?(%__MODULE__{}), do: false

  @doc "Duration in milliseconds of a telemetry event, if it has one."
  @spec duration(t()) :: number() | nil
  def duration(%__MODULE__{type: :telemetry, data: %{measurements: %{duration: duration}}}),
    do: duration

  def duration(%__MODULE__{}), do: nil
end
