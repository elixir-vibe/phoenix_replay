defmodule PhoenixReplay.Web.Components.State do
  @moduledoc """
  The player's **State** tab: the assigns at the current moment, each with
  a one-line preview that expands to the full value when the row cannot
  show it, and what the current event changed inside it, by path, from
  `PhoenixReplay.Recording.Diff`.
  """

  use Phoenix.Component

  import PhoenixIconify, only: [icon: 1]

  alias PhoenixReplay.Web.{Format, Highlight}
  alias PhoenixReplay.Recording.Diff

  # A value expands only when its row cannot show all of it: when the
  # one-line preview leaves something out, or is longer than a row holds.
  @short_value 40
  # How many changes an assign lists under its row before "and N more".
  @shown_changes 8

  @doc "The view's assigns at the current moment, marking the ones it set."
  attr :assigns, :map, required: true, doc: "the replayed assigns"
  attr :changed, :list, required: true, doc: "the keys the current event set"
  attr :before, :map, default: %{}, doc: "the assigns before the current event"
  attr :at, :integer, required: true

  @spec state(map()) :: Phoenix.LiveView.Rendered.t()
  def state(assigns) do
    %{assigns: values, before: before, changed: changed} = assigns

    rows =
      values
      |> Enum.sort()
      |> Enum.map(fn {key, _value} = assign -> state_row(assign, before, key in changed) end)

    assigns = assign(assigns, :rows, rows)

    ~H"""
    <div class="flex items-center justify-between gap-3 border-b border-line px-3.5 py-3">
      <span class="text-sm font-medium">Assigns at {Format.precise_clock(@at)}</span>
      <span :if={@changed != []} class="text-xs text-muted">Changed here are marked</span>
    </div>
    <ul
      id="replay-assigns"
      class="max-h-[calc(100dvh-12rem)] min-h-60 overflow-y-auto py-2 font-mono text-xs"
    >
      <li :for={row <- @rows}>
        <details :if={row.full} class="group">
          <summary class="cursor-pointer list-none">
            <div
              data-assign={row.key}
              class={[
                "grid grid-cols-[0.75rem_minmax(0,8rem)_minmax(0,1fr)] gap-2 px-3.5 py-1.5 hover:bg-hover",
                row.key in @changed && "bg-accent-soft"
              ]}
            >
              <.icon
                name="lucide:chevron-right"
                class="mt-0.5 size-3 text-muted transition-transform group-open:rotate-90"
              />
              <span class={["truncate", row.key in @changed && "text-accent"]}>{row.key}</span>
              <span class="truncate">{row.preview}</span>
            </div>
            <%!-- What changed stays in view whether the value is open or not. --%>
            <.changes :if={row.changes != []} key={row.key} changes={row.changes} more={row.more} />
          </summary>
          <pre
            :if={!row.lines}
            class="mx-3.5 my-1 overflow-x-auto rounded-md bg-canvas p-2.5 leading-relaxed whitespace-pre-wrap text-ink"
          >{row.full}</pre>
          <pre
            :if={row.lines}
            data-diff
            class="mx-3.5 my-1 overflow-x-auto rounded-md bg-canvas py-2 leading-relaxed whitespace-pre-wrap text-ink"
          ><.diff_line :for={line <- row.lines} line={line} /></pre>
        </details>
        <div
          :if={!row.full}
          data-assign={row.key}
          class={[
            "grid grid-cols-[0.75rem_minmax(0,8rem)_minmax(0,1fr)] gap-2 px-3.5 py-1.5",
            row.key in @changed && "bg-accent-soft"
          ]}
        >
          <span></span>
          <span class={["truncate", row.key in @changed && "text-accent"]}>{row.key}</span>
          <span>{row.preview}</span>
        </div>
        <.changes
          :if={!row.full and row.changes != []}
          key={row.key}
          changes={row.changes}
          more={row.more}
        />
      </li>
    </ul>
    """
  end

  attr :key, :any, required: true
  attr :changes, :list, required: true
  attr :more, :integer, required: true

  defp changes(assigns) do
    ~H"""
    <ul data-changes={@key} class="mx-3.5 mb-1.5 ml-8 space-y-0.5">
      <li
        :for={{change, path} <- Enum.map(@changes, &{&1, Diff.path(@key, elem(&1, 1))})}
        class="flex min-w-0 items-baseline gap-2"
      >
        <span class={["w-3 shrink-0 text-center", change_class(change)]}>{change_mark(change)}</span>
        <span class="max-w-[70%] shrink-0 truncate text-muted" title={path}>{path}</span>
        <span class="min-w-0 truncate">{change_values(change)}</span>
      </li>
      <li :if={@more > 0} class="ml-5 text-muted">and {@more} more</li>
    </ul>
    """
  end

  attr :line, :any, required: true

  defp diff_line(%{line: {:skip, count}} = assigns) do
    assigns = assign(assigns, :count, count)

    ~H"""
    <span class="block px-2.5 text-faint">⋯ {Format.count(@count, "unchanged line")}</span>
    """
  end

  defp diff_line(%{line: {op, text}} = assigns) do
    assigns = assign(assigns, op: op, text: text)

    ~H"""
    <span data-op={@op} class={["block px-2.5", diff_line_class(@op)]}><span class="mr-2 inline-block w-2 text-muted select-none">{diff_mark(@op)}</span>{@text}</span>
    """
  end

  defp state_row({key, value}, before, changed?) do
    preview = inspect(value, limit: 8, printable_limit: 80)
    full = inspect(value, pretty: true, limit: 50)
    expand? = full != preview or String.length(preview) > @short_value

    # What the current event changed, when the assign was there before it.
    {changes, lines} =
      case before do
        %{^key => old} when changed? and old != value ->
          {Diff.changes(old, value), if(expand?, do: Diff.lines(old, value, limit: 50))}

        %{} ->
          {[], nil}
      end

    %{
      key: key,
      preview: Highlight.code(preview, :elixir),
      full: if(expand?, do: Highlight.code(full, :elixir)),
      changes: Enum.take(changes, @shown_changes),
      more: max(length(changes) - @shown_changes, 0),
      lines: lines
    }
  end

  defp change_mark({:changed, _path, _old, _new}), do: "~"
  defp change_mark({:added, _path, _new}), do: "+"
  defp change_mark({:removed, _path, _old}), do: "−"

  defp change_class({:changed, _path, _old, _new}), do: "text-accent"
  defp change_class({:added, _path, _new}), do: "text-live"
  defp change_class({:removed, _path, _old}), do: "text-error"

  defp change_values({:changed, _path, old, new}),
    do: [
      Highlight.term(old, limit: 5, printable_limit: 40),
      " → ",
      Highlight.term(new, limit: 5, printable_limit: 40)
    ]

  defp change_values({_op, _path, value}),
    do: Highlight.term(value, limit: 5, printable_limit: 40)

  defp diff_mark(:del), do: "−"
  defp diff_mark(:ins), do: "+"
  defp diff_mark(:eq), do: " "

  defp diff_line_class(:del), do: "bg-error-soft text-error"
  defp diff_line_class(:ins), do: "bg-live-soft text-live"
  defp diff_line_class(:eq), do: nil
end
