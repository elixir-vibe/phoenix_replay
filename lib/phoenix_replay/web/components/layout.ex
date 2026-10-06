defmodule PhoenixReplay.Web.Components.Layout do
  @moduledoc """
  How the dashboard's pages are laid out: the bar across the top, panels
  and tabs, flash messages, progress, empty states, name–value lists and
  pagination. The controls inside them are `PhoenixReplay.Web.Components.Core`.
  """

  use Phoenix.Component

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
