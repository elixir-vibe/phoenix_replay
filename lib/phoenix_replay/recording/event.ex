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
      language: :sql | nil, measurements: map, metadata: map,
      error: String.t() | nil, mark: boolean | String.t()}`, a telemetry
      event captured by a `PhoenixReplay.Collector`; `language` is what the
      summary is written in, and `mark` whether it marks a moment, or the
      mark's name, both absent from events recorded before 0.6
    * `:log` — `%{level: Logger.level(), message: String.t(), metadata: map}`,
      a log message, see `PhoenixReplay.Capture.Logs`
    * `:exit` — `%{reason: String.t()}`, the LiveView process exited
      abnormally
    * `:viewport` — `%{width: integer, height: integer, dpr: number}`, the
      browser's viewport changed: once a resize or rotation settled, or
      with the user's next interaction when `replayRecorder` does not run
    * `:pointer` — a batch of pointer moves, presses and scroll offsets,
      when `:pointer` is configured; see `PhoenixReplay.Capture.Pointer` and
      `PhoenixReplay.Recording.PointerTrack`
    * `:state` — state reported by code in the browser, see
      `PhoenixReplay.Capture.State`. Stored as a batch, `%{span: integer,
      entries: [[dt, key, changes]]}`; `PhoenixReplay.Recording.State.spread/1`
      turns it into one `:state` event per entry, `%{key: String.t(),
      changes: map}`, for replay

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
          | :pointer
          | :state

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

  @doc """
  Returns true for a telemetry event that marks a moment, such as a signup,
  rather than measuring work; see `PhoenixReplay.Collector.Captured`.
  """
  @spec mark?(t()) :: boolean()
  def mark?(%__MODULE__{} = event), do: mark_name(event) != nil

  @doc """
  The name of the moment an event marks: the name its collector gave it,
  or else its telemetry event's name joined with dots, such as
  `"my_app.checkout.completed"`. `nil` for events that mark nothing.
  """
  @spec mark_name(t()) :: String.t() | nil
  def mark_name(%__MODULE__{type: :telemetry, data: %{mark: name}}) when is_binary(name),
    do: name

  def mark_name(%__MODULE__{type: :telemetry, data: %{mark: true, event: event}}),
    do: Enum.map_join(event, ".", &Atom.to_string/1)

  def mark_name(%__MODULE__{}), do: nil

  @doc "One line describing the event; see `PhoenixReplay.Recording.Label`."
  @spec label(t()) :: String.t()
  defdelegate label(event), to: PhoenixReplay.Recording.Label, as: :of

  @doc """
  The assigns an event set: a mount's or render's, or the client state an
  entry reported.
  """
  @spec changed_keys(t() | nil) :: [atom()]
  def changed_keys(%__MODULE__{type: type, data: %{assigns: assigns}})
      when type in [:mount, :render],
      do: Map.keys(assigns)

  def changed_keys(%__MODULE__{type: :state}), do: [PhoenixReplay.Recording.State.assign()]
  def changed_keys(_event), do: []

  @doc "Duration in milliseconds of a telemetry event, if it has one."
  @spec duration(t()) :: number() | nil
  def duration(%__MODULE__{type: :telemetry, data: %{measurements: %{duration: duration}}}),
    do: duration

  def duration(%__MODULE__{}), do: nil
end
