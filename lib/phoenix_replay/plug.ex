defmodule PhoenixReplay.Plug do
  @moduledoc """
  Keeps request context for the visit, so recordings can carry it.

  LiveView sees only some request details when it connects. This plug
  sees every request of the visit, copies what `:context` asks for into
  the session, and `PhoenixReplay.Recorder` adds it to each recording's
  `client` on the connected mount. Add it to the pipeline your live
  sessions use, after `:fetch_session`:

      pipeline :browser do
        plug :accepts, ["html"]
        plug :fetch_session
        # ...
        plug PhoenixReplay.Plug
      end

  With no `:context` configured, it does nothing.

  ## What it keeps

    * **headers** — the `:headers` allowlist, from the latest request,
      each value cut to 256 characters
    * **landing** — the visit's landing request, when `:landing` is
      configured: its URL path and time, the tracked query params, and the
      `Referer`. With `attribution: :first` it is written once per visit;
      with `:last` a request carrying tracked params replaces it.

  A visit lasts as long as the session cookie. The session is rewritten
  only when the kept context changes. Only `GET` requests are landings.
  """

  @behaviour Plug

  import Plug.Conn, only: [get_req_header: 2, get_session: 2, put_session: 3]

  alias PhoenixReplay.Config

  @key "phoenix_replay"
  @max_value 256

  @doc "The session key the context is kept under."
  @spec session_key() :: String.t()
  def session_key, do: @key

  @impl true
  def init(opts), do: opts

  @impl true
  def call(conn, _opts) do
    case Config.load().context do
      %{headers: [], landing: nil} -> conn
      context -> keep(conn, context)
    end
  end

  defp keep(conn, context) do
    kept = get_session(conn, @key) || %{}

    updated =
      kept
      |> put_headers(conn, context.headers)
      |> put_landing(conn, context.landing)

    if updated == kept, do: conn, else: put_session(conn, @key, updated)
  end

  defp put_headers(kept, _conn, []), do: kept

  defp put_headers(kept, conn, names) do
    headers =
      for name <- names, [value | _rest] <- [get_req_header(conn, name)], into: %{} do
        {name, cut(value)}
      end

    Map.put(kept, "headers", headers)
  end

  defp put_landing(kept, _conn, nil), do: kept
  defp put_landing(kept, %{method: method}, _landing) when method != "GET", do: kept

  defp put_landing(kept, conn, landing) do
    params = tracked_params(conn, landing.params)

    if landing?(kept, params, landing.attribution) do
      Map.put(kept, "landing", %{
        "path" => conn.request_path,
        "at" => System.system_time(:millisecond),
        "params" => params,
        "referrer" => referrer(conn, landing.referrer)
      })
    else
      kept
    end
  end

  defp landing?(%{"landing" => _landing}, params, :last), do: params != %{}
  defp landing?(%{"landing" => _landing}, _params, :first), do: false
  defp landing?(_kept, _params, _attribution), do: true

  defp tracked_params(_conn, []), do: %{}

  defp tracked_params(conn, names) do
    query = Plug.Conn.fetch_query_params(conn).query_params
    for name <- names, value = query[name], is_binary(value), into: %{}, do: {name, cut(value)}
  end

  defp referrer(_conn, false), do: nil

  defp referrer(conn, mode) do
    case get_req_header(conn, "referer") do
      [referrer | _rest] -> referrer |> strip(mode) |> cut()
      [] -> nil
    end
  end

  # Query strings often carry tokens, so they are kept only on request.
  defp strip(referrer, :full), do: referrer

  defp strip(referrer, true),
    do: URI.to_string(%{URI.parse(referrer) | query: nil, fragment: nil})

  defp cut(value), do: String.slice(value, 0, @max_value)
end
