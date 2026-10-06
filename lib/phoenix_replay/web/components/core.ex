defmodule PhoenixReplay.Web.Components.Core do
  @moduledoc """
  Building blocks of the dashboard that know nothing about recordings.
  These are its controls; how pages are laid out is
  `PhoenixReplay.Web.Components.Layout`, keycaps are in
  `PhoenixReplay.Web.Components.Keys`, and dialogs in
  `PhoenixReplay.Web.Components.Dialog`.

  Colours come only from the theme tokens in `priv/css/dashboard.css`, such
  as `bg-surface`, `border-line` and `text-muted`, so dark mode needs no
  changes here. Variant classes are written out whole, because Tailwind
  generates only the classes it finds in the source.

  Icons are passed as slot content, `<.icon name="lucide:…" />`, so
  `PhoenixIconify` finds every name at compile time.
  """

  use Phoenix.Component

  import PhoenixIconify, only: [icon: 1]
  import PhoenixReplay.Web.Components.Keys, only: [aria_keyshortcuts: 1, kbd: 1]

  alias Phoenix.LiveView.JS

  @button_variants %{
    "primary" => "border-transparent bg-ink text-on-ink hover:bg-ink/85",
    "secondary" => "border-line bg-surface text-ink hover:bg-hover",
    "danger" => "border-error/30 bg-surface text-error hover:bg-error-soft",
    "ghost" => "border-transparent text-muted hover:bg-hover hover:text-ink"
  }

  @button_sizes %{
    "sm" => "h-8 gap-1.5 px-2.5 text-xs",
    "md" => "h-9 gap-2 px-3 text-sm"
  }

  @doc "A button, with an optional icon before its label."
  attr :variant, :string, values: Map.keys(@button_variants), default: "secondary"
  attr :size, :string, values: Map.keys(@button_sizes), default: "sm"
  attr :type, :string, default: "button"
  attr :class, :any, default: nil
  attr :rest, :global, include: ~w(disabled form name value)
  slot :inner_block, required: true

  @spec button(map()) :: Phoenix.LiveView.Rendered.t()
  def button(assigns) do
    assigns =
      assign(assigns,
        variant_class: @button_variants[assigns.variant],
        size_class: @button_sizes[assigns.size]
      )

    ~H"""
    <button
      type={@type}
      class={[
        "inline-flex shrink-0 items-center justify-center rounded-md border font-medium whitespace-nowrap transition-colors pointer-coarse:min-h-11",
        "disabled:pointer-events-none disabled:opacity-40",
        @variant_class,
        @size_class,
        @class
      ]}
      {@rest}
    >
      {render_slot(@inner_block)}
    </button>
    """
  end

  @icon_button_sizes %{
    "md" => "size-8 rounded-md pointer-coarse:size-11",
    "lg" => "size-11 rounded-full"
  }

  @doc """
  Switches the dashboard between its light and dark themes, overriding the
  system's appearance; the choice is kept in the browser. See
  `priv/ts/dom/theme.ts`.
  """
  attr :rest, :global

  @spec theme_toggle(map()) :: Phoenix.LiveView.Rendered.t()
  def theme_toggle(assigns) do
    ~H"""
    <.icon_button label="Switch theme" variant="ghost" tooltip="bottom" data-theme-toggle {@rest}>
      <.icon name="lucide:moon" class="size-4 dark:hidden" />
      <.icon name="lucide:sun" class="hidden size-4 dark:block" />
    </.icon_button>
    """
  end

  @doc """
  A square button showing only an icon. `label` names it for assistive
  technology and as a tooltip.
  """
  attr :label, :string, required: true
  attr :variant, :string, values: ~w(primary secondary ghost), default: "secondary"
  attr :size, :string, values: ~w(md lg), default: "md", doc: "`lg` is round, for main controls"
  attr :class, :any, default: nil

  attr :keys, :list,
    default: nil,
    doc: "the key combinations that do the same, shown in a tooltip; see `kbd/1`"

  attr :tooltip, :string, values: ~w(top bottom), default: "top", doc: "where the tooltip shows"

  attr :rest, :global, include: ~w(disabled)
  slot :inner_block, required: true

  @spec icon_button(map()) :: Phoenix.LiveView.Rendered.t()
  def icon_button(assigns) do
    assigns =
      assign(assigns,
        variant_class: @button_variants[assigns.variant],
        size_class: @icon_button_sizes[assigns.size]
      )

    ~H"""
    <.tooltip label={@label} keys={@keys} position={@tooltip}>
      <button
        type="button"
        aria-label={@label}
        aria-keyshortcuts={@keys && aria_keyshortcuts(@keys)}
        class={[
          "inline-flex shrink-0 items-center justify-center border transition-colors",
          "disabled:pointer-events-none disabled:opacity-40",
          @variant_class,
          @size_class,
          @class
        ]}
        {@rest}
      >
        {render_slot(@inner_block)}
      </button>
    </.tooltip>
    """
  end

  @badge_tones %{
    "neutral" => "bg-hover text-muted",
    "live" => "bg-live-soft text-live",
    "error" => "bg-error-soft text-error"
  }

  @doc """
  A short status label. `dot` adds a coloured dot, `"pulse"` one that
  pulses, as for a session still recording.
  """
  attr :tone, :string, values: Map.keys(@badge_tones), default: "neutral"
  attr :dot, :string, values: [nil, "static", "pulse"], default: nil
  attr :rest, :global
  slot :inner_block, required: true

  @spec badge(map()) :: Phoenix.LiveView.Rendered.t()
  def badge(assigns) do
    assigns = assign(assigns, :tone_class, @badge_tones[assigns.tone])

    ~H"""
    <span
      class={[
        "inline-flex items-center gap-1.5 rounded-full px-2 py-0.5 text-xs font-medium whitespace-nowrap",
        @tone_class
      ]}
      {@rest}
    >
      <span
        :if={@dot}
        class={["size-1.5 rounded-full bg-current", @dot == "pulse" && "animate-pulse"]}
      ></span>
      {render_slot(@inner_block)}
    </span>
    """
  end

  @doc """
  A pill that toggles something on and off. A `"show"` chip shows a kind
  of thing while pressed and crosses it out otherwise; an `"only"` chip
  narrows to its kind while pressed, in its `tone`.
  """
  attr :pressed, :boolean, required: true
  attr :mode, :string, values: ~w(show only), default: "show"
  attr :tone, :string, values: ~w(neutral error), default: "neutral"
  attr :rest, :global
  slot :inner_block, required: true

  @spec chip(map()) :: Phoenix.LiveView.Rendered.t()
  def chip(assigns) do
    ~H"""
    <button
      type="button"
      aria-pressed={to_string(@pressed)}
      class={[
        "inline-flex h-6 items-center gap-1.5 rounded-full border px-2.5 text-xs whitespace-nowrap transition-colors pointer-coarse:h-9",
        @mode == "show" && @pressed && "border-line bg-hover text-ink",
        @mode == "show" && !@pressed &&
          "border-dashed border-line text-faint line-through hover:text-muted",
        @mode == "only" && !@pressed && "border-line text-ink hover:bg-hover",
        @mode == "only" && @pressed && @tone == "neutral" && "border-ink bg-ink text-on-ink",
        @mode == "only" && @pressed && @tone == "error" && "border-error bg-error-soft text-error"
      ]}
      {@rest}
    >
      {render_slot(@inner_block)}
    </button>
    """
  end

  @doc """
  A row of mutually exclusive options. Clicking one sends `event` with the
  option's value as `value`, from the button's own `value`: LiveView sends a
  clicked button's value under that key, over any `phx-value-value`.
  """
  attr :label, :string, required: true, doc: "names the group for assistive technology"
  attr :options, :list, required: true, doc: "`{value, label}` pairs"
  attr :value, :string, required: true
  attr :event, :string, required: true

  attr :keys, :map,
    default: %{},
    doc: "key combinations by option value, shown in each option's tooltip"

  @spec segmented(map()) :: Phoenix.LiveView.Rendered.t()
  def segmented(assigns) do
    ~H"""
    <div role="group" aria-label={@label} class="inline-flex rounded-md border border-line text-xs">
      <.tooltip
        :for={{value, label} <- @options}
        label={"#{@label}: #{label}"}
        keys={@keys[value]}
        enabled={Map.has_key?(@keys, value)}
      >
        <button
          type="button"
          phx-click={@event}
          value={value}
          aria-pressed={to_string(value == @value)}
          aria-keyshortcuts={@keys[value] && aria_keyshortcuts(@keys[value])}
          class={[
            "h-7 px-2.5 transition-colors group-first/tip:rounded-l-[5px] group-last/tip:rounded-r-[5px] pointer-coarse:h-11",
            value == @value && "bg-ink text-on-ink",
            value != @value && "text-muted hover:bg-hover hover:text-ink"
          ]}
        >
          {label}
        </button>
      </.tooltip>
    </div>
    """
  end

  @doc """
  Shows `label`, and the first of `keys` as keycaps, in a small dark
  tooltip over the control in its slot, on hover and keyboard focus. It is
  hidden from assistive technology: the control names itself, with
  `aria-label` and `aria-keyshortcuts`. Without `enabled`, it renders the
  control alone.

  `position` is the side it prefers: Floating UI places it there, or on
  the other side when there is no room, within the window, as it shows;
  see `priv/ts/dom/floating.ts`.
  """
  attr :label, :string, required: true
  attr :keys, :list, default: nil, doc: "key combinations; the tooltip shows the first"
  attr :position, :string, values: ~w(top bottom), default: "top"
  attr :enabled, :boolean, default: true
  slot :inner_block, required: true

  @spec tooltip(map()) :: Phoenix.LiveView.Rendered.t()
  def tooltip(assigns) do
    ~H"""
    <span class="group/tip inline-flex" data-tip={@enabled}>
      {render_slot(@inner_block)}
      <span
        :if={@enabled}
        aria-hidden="true"
        data-tip-content
        data-placement={@position}
        class={[
          "pointer-events-none fixed top-0 left-0 z-50 not-data-placed:invisible inline-flex w-max items-center gap-1.5 rounded-md bg-ink px-2 py-1 text-xs whitespace-nowrap text-on-ink opacity-0 shadow-md transition-opacity",
          "group-hover/tip:opacity-100 group-hover/tip:delay-300 group-has-focus-visible/tip:opacity-100"
        ]}
      >
        {@label}
        <.kbd :if={@keys} keys={hd(@keys)} tone="inverted" />
      </span>
    </span>
    """
  end

  @doc """
  A time shown in the viewer's time zone by the `LocalTime` hook, as
  `format` says: `"datetime"`, such as "Oct 6, 14:05", or `"date"`, such
  as "Oct 6"; `"title"` keeps the text in the slot, such as "12 s ago".
  Its tooltip has the full time in the viewer's zone and in UTC. Until the
  hook runs, and without JavaScript, the slot's text shows, in UTC.
  """
  attr :id, :string, required: true
  attr :at, :integer, required: true, doc: "Unix milliseconds"
  attr :format, :string, values: ~w(datetime date title), default: "datetime"
  attr :class, :any, default: nil
  slot :inner_block, required: true

  @spec local_time(map()) :: Phoenix.LiveView.Rendered.t()
  def local_time(assigns) do
    time = DateTime.from_unix!(assigns.at, :millisecond)

    assigns =
      assign(assigns,
        iso: DateTime.to_iso8601(time),
        utc: Calendar.strftime(time, "%Y-%m-%d %H:%M:%S UTC")
      )

    ~H"""
    <time
      id={@id}
      phx-hook="LocalTime"
      datetime={@iso}
      data-format={@format}
      title={@utc}
      class={@class}
    >{render_slot(@inner_block)}</time>
    """
  end

  @doc """
  A button that opens a short list of actions, closed again by a click
  elsewhere or Escape. `label` names the button; `trigger_class` styles
  it, by default as an icon button. The list opens below the button, or
  above it without room there, placed by the `Floating` hook.
  """
  attr :id, :string, required: true
  attr :label, :string, required: true

  attr :trigger_class, :string,
    default:
      "inline-flex size-9 items-center justify-center rounded-md border border-line text-muted transition-colors hover:bg-hover hover:text-ink pointer-coarse:size-11"

  slot :trigger, required: true

  slot :item, required: true do
    attr :tone, :string, values: ~w(default danger)
  end

  @spec menu(map()) :: Phoenix.LiveView.Rendered.t()
  def menu(assigns) do
    ~H"""
    <%!-- Clicks on the trigger are not "away", so it alone toggles the menu. --%>
    <div
      class="relative"
      phx-click-away={close_menu(@id)}
      phx-window-keydown={close_menu(@id)}
      phx-key="Escape"
    >
      <button
        id={"#{@id}-button"}
        type="button"
        aria-label={@label}
        title={@label}
        aria-haspopup="menu"
        aria-expanded="false"
        aria-controls={"#{@id}-items"}
        phx-click={toggle_menu(@id)}
        class={@trigger_class}
      >
        {render_slot(@trigger)}
      </button>
      <div
        id={"#{@id}-items"}
        role="menu"
        aria-labelledby={"#{@id}-button"}
        phx-hook="Floating"
        data-anchor={"#{@id}-button"}
        data-placement="bottom-end"
        class="fixed top-0 left-0 z-40 hidden min-w-48 rounded-lg border border-line bg-surface p-1 shadow-lg data-open:block"
      >
        <div
          :for={item <- @item}
          role="none"
          phx-click={close_menu(@id)}
          class={[
            "rounded-md text-sm [&>*]:flex [&>*]:w-full [&>*]:items-center [&>*]:gap-2 [&>*]:px-3 [&>*]:py-2 [&>*]:text-left pointer-coarse:[&>*]:py-3",
            item[:tone] == "danger" && "text-error hover:bg-error-soft",
            item[:tone] != "danger" && "text-ink hover:bg-hover"
          ]}
        >
          {render_slot(item)}
        </div>
      </div>
    </div>
    """
  end

  defp toggle_menu(id) do
    %JS{}
    |> JS.toggle_attribute({"data-open", "true"}, to: "##{id}-items")
    |> JS.toggle_attribute({"aria-expanded", "true", "false"}, to: "##{id}-button")
  end

  @doc """
  Closes the `menu/1` with `id` after `js`. LiveView runs only the
  nearest `phx-click`, so an item with its own chains this to close the
  menu too. Unspecced, like Phoenix's own `JS` helpers: `JS.t()` is
  opaque to Dialyzer.
  """
  def close_menu(js \\ %JS{}, id) do
    js
    |> JS.remove_attribute("data-open", to: "##{id}-items")
    |> JS.set_attribute({"aria-expanded", "false"}, to: "##{id}-button")
  end
end
