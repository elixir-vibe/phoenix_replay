defmodule PhoenixReplay.Web.Components.Keys do
  @moduledoc """
  Keyboard shortcuts as the dashboard shows them: keycaps, and the value
  of `aria-keyshortcuts` that names them for assistive technology. The
  shortcuts themselves are `PhoenixReplay.Web.Player.Shortcuts`.
  """

  use Phoenix.Component

  @key_glyphs %{
    "ArrowLeft" => {"←", "Left arrow"},
    "ArrowRight" => {"→", "Right arrow"},
    "ArrowUp" => {"↑", "Up arrow"},
    "ArrowDown" => {"↓", "Down arrow"},
    "Escape" => {"Esc", nil},
    "Space" => {"Space", nil}
  }

  @doc """
  A keyboard shortcut as keycaps: one `<kbd>` per key inside one for the
  combination, as HTML nests them. `keys` is one combination, such as
  `["Shift", "ArrowRight"]`, in the browser's key names
  (`KeyboardEvent.key`, with `"Space"` for the space bar). Arrows show as
  glyphs, with their name for screen readers; letters show capitalized,
  and named keys such as `Shift` and `Home` as words.
  """
  attr :keys, :list, required: true
  attr :size, :string, values: ~w(sm md), default: "sm"

  attr :tone, :string,
    values: ~w(default inverted),
    default: "default",
    doc: "`inverted` on dark surfaces"

  attr :class, :any, default: nil

  @spec kbd(map()) :: Phoenix.LiveView.Rendered.t()
  def kbd(assigns) do
    ~H"""
    <kbd class={["inline-flex items-center gap-0.5 align-baseline", @class]}>
      <kbd
        :for={key <- @keys}
        class={[
          "inline-flex items-center justify-center rounded border border-b-2 font-mono leading-none",
          @size == "sm" && "h-[1.15rem] min-w-[1.15rem] px-1 text-[0.7rem]",
          @size == "md" && "h-6 min-w-6 px-1.5 text-xs",
          @tone == "default" && "border-line bg-surface text-muted",
          @tone == "inverted" && "border-on-ink/30 bg-on-ink/10 text-on-ink"
        ]}
      >
        <%= case key_glyph(key) do %>
          <% {glyph, nil} -> %>
            {glyph}
          <% {glyph, name} -> %>
            <span aria-hidden="true">{glyph}</span><span class="sr-only">{name}</span>
          <% nil -> %>
            {key_label(key)}
        <% end %>
      </kbd>
    </kbd>
    """
  end

  defp key_glyph(key), do: Map.get(@key_glyphs, key)

  # Letters show capitalized, as on keycaps; named keys, such as Shift, as words.
  defp key_label(key) when byte_size(key) == 1, do: String.upcase(key)
  defp key_label(key), do: key

  @doc """
  The value of `aria-keyshortcuts` for key combinations, such as
  `"Space K"`, each combination's keys joined with `+`.
  """
  @spec aria_keyshortcuts([[String.t()]]) :: String.t()
  def aria_keyshortcuts(combinations),
    do: Enum.map_join(combinations, " ", &Enum.join(&1, "+"))
end
