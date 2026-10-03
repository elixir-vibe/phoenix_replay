defmodule PhoenixReplay.Recording.Event do
  @moduledoc """
  A single entry in a recording's timeline.

  `at` is the offset in milliseconds from the moment recording started.
  The shape of `data` depends on `type`:

    * `:mount` — `%{assigns: map}`, the assigns when recording started
    * `:event` — `%{name: String.t(), params: map}`, a `handle_event/3` call
    * `:params` — `%{params: map, uri: String.t()}`, a `handle_params/3` call
    * `:info` — `%{tag: atom | nil}`, a `handle_info/2` call; only the message
      tag is kept so arbitrary message contents are never stored
    * `:render` — `%{assigns: map}`, the assigns changed by a render
  """

  @type type :: :mount | :event | :params | :info | :render

  @type t :: %__MODULE__{at: non_neg_integer(), type: type(), data: map()}

  @enforce_keys [:at, :type]
  defstruct [:at, :type, data: %{}]
end
