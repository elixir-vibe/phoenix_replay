defmodule PhoenixReplay.Web.Components.Dialog do
  @moduledoc """
  The dashboard's modal dialog, which the export dialog and the shortcut
  sheet are built on.
  """

  use Phoenix.Component

  import PhoenixIconify, only: [icon: 1]
  import PhoenixReplay.Web.Components.Core, only: [icon_button: 1]

  alias Phoenix.LiveView.JS

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
end
