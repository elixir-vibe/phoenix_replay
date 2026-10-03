defmodule PhoenixReplay.Test.Endpoint do
  @moduledoc "Endpoint serving the test router."

  use Phoenix.Endpoint, otp_app: :phoenix_replay

  @session_options [store: :cookie, key: "_replay_test", signing_salt: "test_salt"]

  socket "/live", Phoenix.LiveView.Socket, websocket: [connect_info: [session: @session_options]]

  plug Plug.Session, @session_options
  plug PhoenixReplay.Test.Router
end
