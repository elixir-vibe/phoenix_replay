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

  @doc """
  A square button showing only an icon. `label` names it for assistive
  technology and as a tooltip.
  """
  attr :label, :string, required: true
  attr :variant, :string, values: ~w(secondary ghost), default: "secondary"
  attr :class, :any, default: nil
  attr :rest, :global, include: ~w(disabled)
  slot :inner_block, required: true

  @spec icon_button(map()) :: Phoenix.LiveView.Rendered.t()
  def icon_button(assigns) do
    assigns = assign(assigns, :variant_class, @button_variants[assigns.variant])

    ~H"""
    <button
      type="button"
      aria-label={@label}
      title={@label}
      class={[
        "inline-flex size-8 shrink-0 items-center justify-center rounded-md border transition-colors pointer-coarse:size-11",
        "disabled:pointer-events-none disabled:opacity-40",
        @variant_class,
        @class
      ]}
      {@rest}
    >
      {render_slot(@inner_block)}
    </button>
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

  @doc "A pill that toggles something on and off, such as a filter."
  attr :pressed, :boolean, required: true
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
        @pressed && "border-line bg-hover text-ink",
        !@pressed && "border-dashed border-line text-faint line-through hover:text-muted"
      ]}
      {@rest}
    >
      {render_slot(@inner_block)}
    </button>
    """
  end

  @doc """
  A row of mutually exclusive options. Clicking one sends `event` with the
  option's value as `value`.
  """
  attr :label, :string, required: true, doc: "names the group for assistive technology"
  attr :options, :list, required: true, doc: "`{value, label}` pairs"
  attr :value, :string, required: true
  attr :event, :string, required: true

  @spec segmented(map()) :: Phoenix.LiveView.Rendered.t()
  def segmented(assigns) do
    ~H"""
    <div
      role="group"
      aria-label={@label}
      class="inline-flex overflow-hidden rounded-md border border-line text-xs"
    >
      <button
        :for={{value, label} <- @options}
        type="button"
        phx-click={@event}
        phx-value-value={value}
        aria-pressed={to_string(value == @value)}
        class={[
          "h-7 px-2.5 transition-colors pointer-coarse:h-11",
          value == @value && "bg-ink text-on-ink",
          value != @value && "text-muted hover:bg-hover hover:text-ink"
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
  elsewhere or Escape. `label` names the button.
  """
  attr :id, :string, required: true
  attr :label, :string, required: true
  slot :trigger, required: true

  slot :item, required: true do
    attr :tone, :string, values: ~w(default danger)
  end

  @spec menu(map()) :: Phoenix.LiveView.Rendered.t()
  def menu(assigns) do
    ~H"""
    <div class="relative">
      <button
        id={"#{@id}-button"}
        type="button"
        aria-label={@label}
        title={@label}
        aria-haspopup="menu"
        aria-expanded="false"
        aria-controls={"#{@id}-items"}
        phx-click={toggle_menu(@id)}
        class="inline-flex size-9 items-center justify-center rounded-md border border-line text-muted transition-colors hover:bg-hover hover:text-ink pointer-coarse:size-11"
      >
        {render_slot(@trigger)}
      </button>
      <div
        id={"#{@id}-items"}
        role="menu"
        aria-labelledby={"#{@id}-button"}
        phx-click-away={close_menu(@id)}
        phx-window-keydown={close_menu(@id)}
        phx-key="Escape"
        class="absolute right-0 z-20 mt-1 hidden min-w-48 rounded-lg border border-line bg-surface p-1 shadow-lg"
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
    |> JS.toggle(to: "##{id}-items")
    |> JS.toggle_attribute({"aria-expanded", "true", "false"}, to: "##{id}-button")
  end

  defp close_menu(id) do
    %JS{}
    |> JS.hide(to: "##{id}-items")
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
        <dd class="break-all text-ink">{render_slot(item)}</dd>
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
