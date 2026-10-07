defmodule ExampleWeb.Theme do
  @moduledoc """
  The theme a visitor chose: `"system"`, `"light"` or `"dark"`, kept on the
  server, so recordings carry it like any other assign.

  The plug reads it from the `theme` cookie into the session and `@theme`,
  which the root layout renders as `data-theme`. The `on_mount` hook gives
  each LiveView `@theme` and handles the toggle's `"theme"` event: it
  updates the assign and pushes `"theme"`, whose listener in app.ts sets
  `data-theme` at once and keeps the choice in the cookie for the next
  page load.

  Replays need nothing more: the replay renders the root layout again with
  each moment's assigns, so the replayed page takes the theme the session
  had then.
  """

  use Phoenix.Component

  import Phoenix.LiveView, only: [attach_hook: 4, push_event: 3]

  @behaviour Plug

  @themes ~w(system light dark)

  @impl Plug
  def init(opts), do: opts

  @impl Plug
  def call(conn, _opts) do
    conn = Plug.Conn.fetch_cookies(conn)
    theme = chosen(conn.cookies["theme"])

    conn
    |> Plug.Conn.put_session("theme", theme)
    |> Plug.Conn.assign(:theme, theme)
  end

  @doc "Gives a LiveView `@theme` and handles the toggle."
  def on_mount(:default, _params, session, socket) do
    socket =
      socket
      |> assign(:theme, chosen(session["theme"]))
      |> attach_hook(:theme, :handle_event, &handle_event/3)

    {:cont, socket}
  end

  defp handle_event("theme", %{"theme" => theme}, socket) when theme in @themes,
    do: {:halt, socket |> assign(:theme, theme) |> push_event("theme", %{theme: theme})}

  defp handle_event(_event, _params, socket), do: {:cont, socket}

  defp chosen(theme) when theme in @themes, do: theme
  defp chosen(_theme), do: "system"

  @doc "Buttons that choose the theme, the chosen one pressed."
  attr :theme, :string, required: true

  def toggle(assigns) do
    ~H"""
    <div
      role="group"
      aria-label="Theme"
      class="inline-flex h-9 items-center rounded-md border border-gray-200 p-0.5"
    >
      <button
        :for={{theme, label} <- [{"system", "Auto"}, {"light", "Light"}, {"dark", "Dark"}]}
        type="button"
        phx-click="theme"
        phx-value-theme={theme}
        aria-pressed={to_string(@theme == theme)}
        class="h-full rounded px-2.5 text-xs font-medium text-gray-500 transition-colors hover:text-gray-900 aria-pressed:bg-gray-100 aria-pressed:text-gray-900"
      >
        {label}
      </button>
    </div>
    """
  end
end
