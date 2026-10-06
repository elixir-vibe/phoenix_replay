defmodule PhoenixReplay.Web.Components.Core do
  @moduledoc """
  Building blocks of the dashboard that know nothing about recordings.

  Colours come only from the theme tokens in `priv/css/dashboard.css`, such
  as `bg-surface`, `border-line` and `text-muted`, so dark mode needs no
  changes here. Variant classes are written out whole, because Tailwind
  generates only the classes it finds in the source.

  Icons are passed as slot content, `<.icon name="lucide:…" />`, so
  `PhoenixIconify` finds every name at compile time.
  """

  use Phoenix.Component

  import PhoenixIconify, only: [icon: 1]

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

  @dialog_sizes %{"md" => "max-w-md", "lg" => "max-w-2xl"}

  @doc """
  A modal dialog over a dimmed page: a header with its title, an optional
  description and a close button, a body that scrolls on its own when it
  is taller than the window, and an optional footer for its actions, which
  stay in view. Escape, a click outside and the close button run `close`,
  an event name or a `JS` command.

  The dialog takes focus when it opens, so the keyboard starts in it; Tab
  goes on to its controls. A footer button submits a form in the body with
  the `form` attribute.
  """
  attr :id, :string, required: true
  attr :title, :string, required: true
  attr :description, :string, default: nil
  attr :close, :any, required: true, doc: "an event name or a `JS` command"
  attr :size, :string, values: Map.keys(@dialog_sizes), default: "md"
  slot :inner_block, required: true
  slot :footer

  @spec dialog(map()) :: Phoenix.LiveView.Rendered.t()
  def dialog(assigns) do
    assigns = assign(assigns, :size_class, @dialog_sizes[assigns.size])

    ~H"""
    <div
      id={@id}
      class="fixed inset-0 z-40 flex items-center justify-center bg-black/40 p-4"
      phx-window-keydown={@close}
      phx-key="Escape"
    >
      <div
        id={"#{@id}-panel"}
        role="dialog"
        aria-modal="true"
        aria-labelledby={"#{@id}-title"}
        aria-describedby={@description && "#{@id}-description"}
        tabindex="-1"
        phx-click-away={@close}
        phx-mounted={JS.focus()}
        class={[
          "flex max-h-full w-full flex-col rounded-xl border border-line bg-surface text-sm shadow-xl outline-none",
          @size_class
        ]}
      >
        <header class="flex items-start gap-3 px-5 pt-4 pb-3">
          <div class="min-w-0 flex-1 pt-1">
            <h2 id={"#{@id}-title"} class="text-base font-semibold">{@title}</h2>
            <p :if={@description} id={"#{@id}-description"} class="mt-1 text-muted">
              {@description}
            </p>
          </div>
          <.icon_button
            label="Close"
            variant="ghost"
            keys={[["Escape"]]}
            tooltip="bottom"
            phx-click={@close}
          >
            <.icon name="lucide:x" class="size-4" />
          </.icon_button>
        </header>
        <div class="min-h-0 flex-1 overflow-y-auto overscroll-contain px-5 pb-5">
          {render_slot(@inner_block)}
        </div>
        <footer
          :if={@footer != []}
          class="flex flex-wrap justify-end gap-2 border-t border-line px-5 py-3"
        >
          {render_slot(@footer)}
        </footer>
      </div>
    </div>
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
  Tabs that switch a panel. Clicking one sends `event` with the tab's value
  as `value`; the panel is the caller's, with `id` plus `-panel`.
  """
  attr :id, :string, required: true
  attr :label, :string, required: true, doc: "names the tabs for assistive technology"
  attr :tabs, :list, required: true, doc: "`{value, label}` pairs"
  attr :value, :string, required: true
  attr :event, :string, required: true

  @spec tabs(map()) :: Phoenix.LiveView.Rendered.t()
  def tabs(assigns) do
    ~H"""
    <div id={@id} role="tablist" aria-label={@label} class="flex gap-1 border-b border-line px-3 pt-2">
      <button
        :for={{value, label} <- @tabs}
        type="button"
        role="tab"
        aria-selected={to_string(value == @value)}
        aria-controls={"#{@id}-panel"}
        phx-click={@event}
        value={value}
        class={[
          "-mb-px h-10 border-b-2 px-3 text-sm font-medium transition-colors pointer-coarse:h-11",
          value == @value && "border-accent text-ink",
          value != @value && "border-transparent text-muted hover:text-ink"
        ]}
      >
        {label}
      </button>
    </div>
    """
  end

  @doc """
  A bordered section with an optional title and actions in its header.
  Without `padded`, the body runs to the edges, for lists and code.
  """
  attr :title, :string, default: nil
  attr :padded, :boolean, default: false
  attr :class, :any, default: nil
  attr :rest, :global
  slot :actions
  slot :inner_block, required: true

  @spec panel(map()) :: Phoenix.LiveView.Rendered.t()
  def panel(assigns) do
    ~H"""
    <section
      class={["flex min-w-0 flex-col rounded-lg border border-line bg-surface", @class]}
      {@rest}
    >
      <header
        :if={@title || @actions != []}
        class="flex min-h-10 items-center gap-2 border-b border-line px-4 py-2"
      >
        <h2 :if={@title} class="text-xs font-medium tracking-wide text-muted uppercase">
          {@title}
        </h2>
        <span class="flex-1"></span>
        {render_slot(@actions)}
      </header>
      <div class={["min-h-0 flex-1", @padded && "p-4"]}>
        {render_slot(@inner_block)}
      </div>
    </section>
    """
  end

  @doc """
  The bar across the top of a page: a mark, a trail of titles and actions.
  """
  attr :rest, :global
  slot :mark, required: true
  slot :crumb, required: true
  slot :actions

  @spec app_bar(map()) :: Phoenix.LiveView.Rendered.t()
  def app_bar(assigns) do
    ~H"""
    <header class="border-b border-line bg-surface" {@rest}>
      <div class="mx-auto flex h-14 max-w-6xl items-center gap-3 px-4 sm:px-6">
        {render_slot(@mark)}
        <%= for {crumb, index} <- Enum.with_index(@crumb) do %>
          <span :if={index > 0} class="text-faint" aria-hidden="true">/</span>
          <span class={["truncate", index == 0 && "font-semibold", index > 0 && "text-muted"]}>
            {render_slot(crumb)}
          </span>
        <% end %>
        <span class="flex-1"></span>
        {render_slot(@actions)}
      </div>
    </header>
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

  @doc "Shows a flash message of `kind`, if there is one."
  attr :flash, :map, required: true
  attr :kind, :atom, values: [:error, :info], default: :error

  @spec flash(map()) :: Phoenix.LiveView.Rendered.t()
  def flash(assigns) do
    ~H"""
    <p
      :if={message = Phoenix.Flash.get(@flash, @kind)}
      role="alert"
      class={[
        "mb-4 rounded-md border px-4 py-2 text-sm",
        @kind == :error && "border-error/30 bg-error-soft text-error",
        @kind == :info && "border-line bg-surface text-ink"
      ]}
    >
      {message}
    </p>
    """
  end

  @doc "A thin progress bar, `value` percent full."
  attr :value, :float, required: true
  attr :label, :string, required: true

  @spec progress(map()) :: Phoenix.LiveView.Rendered.t()
  def progress(assigns) do
    ~H"""
    <div
      role="progressbar"
      aria-label={@label}
      aria-valuemin="0"
      aria-valuemax="100"
      aria-valuenow={@value}
      class="h-1 rounded-full bg-track"
    >
      <div class="h-1 rounded-full bg-ink transition-[width]" style={"width: #{@value}%"}></div>
    </div>
    """
  end

  @doc "Placeholder for a list with nothing to show."
  attr :title, :string, required: true
  attr :rest, :global
  slot :icon
  slot :inner_block
  slot :action

  @spec empty_state(map()) :: Phoenix.LiveView.Rendered.t()
  def empty_state(assigns) do
    ~H"""
    <div class="flex flex-col items-center px-4 py-16 text-center" {@rest}>
      <div :if={@icon != []} class="mb-4 text-faint">{render_slot(@icon)}</div>
      <p class="font-medium text-ink">{@title}</p>
      <div :if={@inner_block != []} class="mt-1 max-w-md text-sm text-muted">
        {render_slot(@inner_block)}
      </div>
      <div :if={@action != []} class="mt-4">{render_slot(@action)}</div>
    </div>
    """
  end

  @doc "Name–value pairs, such as headers or query params."
  attr :class, :any, default: nil
  attr :rest, :global

  slot :item, required: true do
    attr :title, :string, required: true
  end

  @spec data_list(map()) :: Phoenix.LiveView.Rendered.t()
  def data_list(assigns) do
    ~H"""
    <dl
      class={["grid grid-cols-[max-content_minmax(0,1fr)] gap-x-4 gap-y-1 font-mono text-xs", @class]}
      {@rest}
    >
      <%= for item <- @item do %>
        <dt class="text-muted">{item.title}</dt>
        <dd class="wrap-break-word whitespace-pre-wrap text-ink">{render_slot(item)}</dd>
      <% end %>
    </dl>
    """
  end

  @doc """
  Numbered page links, such as `‹ 1 … 4 5 6 … 12 ›`. `path` builds a
  page's URL from its number.
  """
  attr :page, :integer, required: true
  attr :total_pages, :integer, required: true
  attr :path, :any, required: true, doc: "a function from a page number to its URL"

  @spec pagination(map()) :: Phoenix.LiveView.Rendered.t()
  def pagination(assigns) do
    assigns = assign(assigns, :items, page_items(assigns.page, assigns.total_pages))

    ~H"""
    <nav
      :if={@total_pages > 1}
      aria-label="Pagination"
      class="flex items-center justify-center gap-1 text-sm tabular-nums"
    >
      <.page_link
        :if={@page > 1}
        path={@path.(@page - 1)}
        label="Previous page"
      >
        ‹
      </.page_link>
      <%= for item <- @items do %>
        <span :if={item == :gap} class="px-1 text-faint" aria-hidden="true">…</span>
        <.page_link
          :if={item != :gap}
          path={@path.(item)}
          label={"Page #{item}"}
          current={item == @page}
        >
          {item}
        </.page_link>
      <% end %>
      <.page_link
        :if={@page < @total_pages}
        path={@path.(@page + 1)}
        label="Next page"
      >
        ›
      </.page_link>
    </nav>
    """
  end

  attr :path, :string, required: true
  attr :label, :string, required: true
  attr :current, :boolean, default: false
  slot :inner_block, required: true

  defp page_link(assigns) do
    ~H"""
    <.link
      patch={@path}
      aria-label={@label}
      aria-current={@current && "page"}
      class={[
        "inline-flex size-8 items-center justify-center rounded-md transition-colors pointer-coarse:size-11",
        @current && "bg-ink font-medium text-on-ink",
        !@current && "text-muted hover:bg-hover hover:text-ink"
      ]}
    >
      {render_slot(@inner_block)}
    </.link>
    """
  end

  # The first and last pages and the ones around the current one, with a
  # gap for each skipped run. A gap of a single page shows that page.
  defp page_items(page, total) do
    [1, page - 1, page, page + 1, total]
    |> Enum.filter(&(&1 in 1..total//1))
    |> Enum.uniq()
    |> Enum.sort()
    |> Enum.chunk_every(2, 1)
    |> Enum.flat_map(fn
      [a, b] when b - a == 2 -> [a, a + 1]
      [a, b] when b - a > 2 -> [a, :gap]
      [a | _rest] -> [a]
    end)
  end
end
