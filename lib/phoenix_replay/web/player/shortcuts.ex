defmodule PhoenixReplay.Web.Player.Shortcuts do
  @moduledoc """
  The player's keyboard shortcuts, in one place: the `PlayerKeys` hook
  reads them to act on keys, and the player shows them in tooltips, menus
  and the shortcut sheet, so what is shown and what works stay the same.

  Each shortcut has an `id`, its key combinations in the browser's key
  names (`KeyboardEvent.key`, with `"Space"` for the space bar; see
  `PhoenixReplay.Web.Components.Core.kbd/1`), a label, and the group the
  sheet lists it under.
  """

  @typedoc "One key combination, such as `[\"Shift\", \"ArrowRight\"]`."
  @type combination :: [String.t()]

  @type group :: :playback | :moving | :view | :general

  @type t :: %{id: atom(), keys: [combination()], label: String.t(), group: group()}

  @shortcuts [
    %{id: :toggle, keys: [["Space"], ["K"]], label: "Play or pause", group: :playback},
    %{id: :previous, keys: [["ArrowLeft"]], label: "Previous event", group: :moving},
    %{id: :next, keys: [["ArrowRight"]], label: "Next event", group: :moving},
    %{id: :back, keys: [["Shift", "ArrowLeft"]], label: "Back 5 seconds", group: :moving},
    %{
      id: :forward,
      keys: [["Shift", "ArrowRight"]],
      label: "Forward 5 seconds",
      group: :moving
    },
    %{id: :start, keys: [["Home"]], label: "To the start", group: :moving},
    %{id: :end, keys: [["End"]], label: "To the end", group: :moving},
    %{id: :next_error, keys: [["E"]], label: "Next error", group: :moving},
    %{id: :previous_error, keys: [["Shift", "E"]], label: "Previous error", group: :moving},
    %{id: :next_mark, keys: [["M"]], label: "Next mark", group: :moving},
    %{id: :previous_mark, keys: [["Shift", "M"]], label: "Previous mark", group: :moving},
    %{id: :speed_1, keys: [["1"]], label: "Speed 1×", group: :playback},
    %{id: :speed_2, keys: [["2"]], label: "Speed 2×", group: :playback},
    %{id: :speed_5, keys: [["3"]], label: "Speed 5×", group: :playback},
    %{id: :speed_10, keys: [["4"]], label: "Speed 10×", group: :playback},
    %{id: :fit, keys: [["F"]], label: "Fit to window or actual size", group: :view},
    %{id: :rotate, keys: [["R"]], label: "Rotate", group: :view},
    %{id: :pointer, keys: [["P"]], label: "Show or hide the pointer", group: :view},
    %{id: :search, keys: [["/"]], label: "Search events", group: :general},
    %{id: :help, keys: [["?"]], label: "Keyboard shortcuts", group: :general}
  ]

  # Listed in this order, the sheet's two columns come out even: playback
  # and the view on the left, moving around and the rest on the right.
  @groups [playback: "Playback", view: "View", moving: "Moving around", general: "General"]

  @doc "Every shortcut, in the order the sheet lists them."
  @spec all() :: [t()]
  def all, do: @shortcuts

  @doc "The key combinations of the shortcut `id`."
  @spec keys(atom()) :: [combination()]
  def keys(id), do: Enum.find(@shortcuts, &(&1.id == id)).keys

  @doc "The key combinations of the speed shortcuts, by speed, for the speed control."
  @spec speed_keys([pos_integer()]) :: %{String.t() => [combination()]}
  def speed_keys(speeds) do
    for speed <- speeds, into: %{}, do: {Integer.to_string(speed), keys(:"speed_#{speed}")}
  end

  @doc "The shortcuts by group, with each group's heading."
  @spec groups() :: [{String.t(), [t()]}]
  def groups do
    for {group, heading} <- @groups,
        do: {heading, Enum.filter(@shortcuts, &(&1.group == group))}
  end

  @doc "The shortcuts as JSON for the `PlayerKeys` hook: each id and its combinations."
  @spec json() :: String.t()
  def json, do: @shortcuts |> Enum.map(&Map.take(&1, [:id, :keys])) |> JSON.encode!()
end
