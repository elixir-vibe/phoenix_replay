defmodule PhoenixReplay.Web.Export.Endpoint do
  @moduledoc """
  The endpoint the export browser loads replays from.

  `PhoenixReplay.Export.Runtime` starts it with the first export, on
  127.0.0.1 and a free port, with a secret made at that moment and given
  to `start_link/1` rather than kept in the application environment. It serves
  `PhoenixReplay.Web.Export.Router` under `/_phoenix_replay`, where every page
  takes a token signed with that secret, and passes every other request,
  such as the stylesheet a replayed page loads, to your endpoint.
  """

  use Phoenix.Endpoint, otp_app: :phoenix_replay

  alias PhoenixReplay.Config

  @session_options [store: :cookie, key: "_phoenix_replay_export", signing_salt: "export"]

  socket "/_phoenix_replay/live", Phoenix.LiveView.Socket, websocket: true, longpoll: false

  plug Plug.Session, @session_options
  plug :dispatch

  defp dispatch(%Plug.Conn{path_info: ["_phoenix_replay" | _rest]} = conn, _opts),
    do: PhoenixReplay.Web.Export.Router.call(conn, PhoenixReplay.Web.Export.Router.init([]))

  # Your endpoint serves its own assets, in development from whatever
  # builds them.
  defp dispatch(conn, _opts) do
    endpoint = Config.load().export.endpoint
    endpoint.call(conn, endpoint.init([]))
  end
end
