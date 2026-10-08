defmodule PhoenixReplay.Authorization do
  @moduledoc """
  Behaviour for deciding what a dashboard viewer may see and do.

  Pass the module to the router macro:

      phoenix_replay "/replay",
        on_mount: [{MyAppWeb.UserAuth, :ensure_admin}],
        authorize: MyApp.ReplayAuthorization

  The callback receives the action, the subject and the dashboard socket,
  whose assigns include anything set by your own `:on_mount` hooks:

      defmodule MyApp.ReplayAuthorization do
        @behaviour PhoenixReplay.Authorization

        @impl true
        def authorize(:clear, _subject, socket), do: socket.assigns.current_user.admin?
        def authorize(_action, _subject, socket), do: socket.assigns.current_user != nil
      end

  Actions and subjects:

    * `:list` — a `PhoenixReplay.Recording.Summary` shown in the index
    * `:view` — a `PhoenixReplay.Recording` opened for replay
    * `:delete` — a `PhoenixReplay.Recording.Summary` or `PhoenixReplay.Recording`
    * `:clear` — `nil`, deleting every recording

  Without an `:authorize` module every action is allowed, so protect the
  dashboard route with your router pipeline or `:on_mount` hooks.

  Storage pages the recording list itself only without an `:authorize`
  module. With one, the dashboard reads every summary and checks `:list`
  for each, so its pages and counts show exactly what the viewer may see.
  """

  alias PhoenixReplay.Recording
  alias PhoenixReplay.Recording.Summary

  @type action :: :list | :view | :delete | :clear
  @type subject :: Recording.t() | Summary.t() | nil

  @callback authorize(action(), subject(), Phoenix.LiveView.Socket.t()) :: boolean()

  @doc "Calls `module.authorize/3`, allowing everything when `module` is `nil`."
  @spec allowed?(module() | nil, action(), subject(), Phoenix.LiveView.Socket.t()) :: boolean()
  def allowed?(nil, _action, _subject, _socket), do: true

  def allowed?(module, action, subject, socket),
    do: module.authorize(action, subject, socket) == true
end
