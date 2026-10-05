defmodule PhoenixReplay.Export.Endpoint do
  @moduledoc """
  The endpoint the export browser loads replays from.

  `PhoenixReplay.Export.Runtime` starts it with the first export, on
  127.0.0.1 and a free port, with a secret made at that moment. It serves
  `PhoenixReplay.Export.Router` under `/_phoenix_replay`, where every page
  takes a token signed with that secret, and passes every other request,
  such as the stylesheet a replayed page loads, to your endpoint.
  """

  use Phoenix.Endpoint, otp_app: :phoenix_replay

  alias PhoenixReplay.Config

  @session_options [store: :cookie, key: "_phoenix_replay_export", signing_salt: "export"]

  socket "/_phoenix_replay/live", Phoenix.LiveView.Socket, websocket: true, longpoll: false

  plug Plug.Session, @session_options
  plug :dispatch

  @doc """
  The endpoint's configuration, given to `start_link/1` rather than kept
  in the application environment: a loopback address, a free port, and
  secrets made for this start.
  """
  @spec settings() :: keyword()
  def settings do
    [
      adapter: adapter(),
      http: [ip: {127, 0, 0, 1}, port: 0],
      url: [host: "127.0.0.1"],
      server: true,
      secret_key_base: secret(64),
      live_view: [signing_salt: secret(16)],
      pubsub_server: PhoenixReplay.PubSub,
      check_origin: false,
      render_errors: [formats: [html: PhoenixReplay.Export.ErrorHTML], layout: false]
    ]
  end

  # Your app has Bandit or Cowboy; Phoenix serves with either.
  defp adapter do
    if Code.ensure_loaded?(Bandit.PhoenixAdapter),
      do: Bandit.PhoenixAdapter,
      else: Phoenix.Endpoint.Cowboy2Adapter
  end

  defp secret(bytes), do: bytes |> :crypto.strong_rand_bytes() |> Base.url_encode64()

  defp dispatch(%Plug.Conn{path_info: ["_phoenix_replay" | _rest]} = conn, _opts),
    do: PhoenixReplay.Export.Router.call(conn, PhoenixReplay.Export.Router.init([]))

  # Your endpoint serves its own assets, in development from whatever
  # builds them.
  defp dispatch(conn, _opts) do
    endpoint = Config.load().export.endpoint
    endpoint.call(conn, endpoint.init([]))
  end
end
