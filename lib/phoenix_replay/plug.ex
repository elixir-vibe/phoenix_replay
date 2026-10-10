defmodule PhoenixReplay.Plug do
  @moduledoc """
  Keeps the visit and its request context, so recordings can carry them.

  LiveView sees only some request details when it connects. This plug
  sees every request of the visit, keeps the visit and what the `:client`
  config asks for in the session, and `PhoenixReplay.Recorder` adds it to
  each recording's `client` on the connected mount. Add it to the pipeline
  your live sessions use, after `:fetch_session`:

      pipeline :browser do
        plug :accepts, ["html"]
        plug :fetch_session
        # ...
        plug PhoenixReplay.Plug
      end

  ## Visits

  A visit is what web analytics call a session: it starts with a request
  and ends after 30 minutes without one, or when a request arrives with
  campaign params that differ from the visit's landing. Its tabs share it.
  The plug gives each visit an id, which every recording made in it
  carries, so the recordings of one visit are listed, kept and played
  together. `landing: [timeout: ...]` in the `:client` config changes how
  long a visit lasts without a request. Live navigation between LiveViews
  makes no request, so a visit spent in one page longer than the timeout
  ends at its next request.

  The time of the latest request is written when a minute has passed since
  the one kept, so the session is not rewritten on every request, and a
  visit ends up to a minute before its timeout.

  ## What else it keeps

    * **headers** — the `:headers` allowlist, from the latest request,
      each value cut to 256 characters
    * **landing** — the visit's landing request, when `:landing` is
      configured: its URL path and time, the tracked query params, and the
      `Referer`. With `attribution: :first` it is the first `GET` of the
      visit; with `:last` a request carrying tracked params replaces it.

  The session is rewritten only when the kept context changes. Only `GET`
  requests are landings.

  The kept context stays under 1 KB, so a crafted link cannot overflow a
  cookie session: past that, the landing's params are dropped, then the
  headers, then the landing.
  """

  @behaviour Plug

  import Plug.Conn, only: [get_req_header: 2, get_session: 2, put_session: 3]

  alias PhoenixReplay.{Config, Recording}

  @key "phoenix_replay"
  @max_value 256
  @max_kept 1_024
  # How far the kept time of the latest request may lag behind it.
  @seen_step 60_000

  @doc "The session key the context is kept under."
  @spec session_key() :: String.t()
  def session_key, do: @key

  @impl true
  def init(opts), do: opts

  @impl true
  def call(conn, _opts) do
    config = Config.load()
    kept = get_session(conn, @key) || %{}

    updated =
      kept
      |> put_headers(conn, config.client.headers)
      |> put_visit(conn, config, System.system_time(:millisecond))
      |> fit()

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

  defp put_visit(kept, conn, config, now) do
    landing = config.client.landing

    params =
      if landing && conn.method == "GET", do: tracked_params(conn, landing.params), else: %{}

    if new_visit?(kept["visit"], params, Config.visit_timeout(config), now) do
      kept
      |> Map.delete("landing")
      |> Map.put("visit", %{
        "id" => Recording.generate_id(),
        "seen" => now,
        "campaign" => campaign(params)
      })
      |> put_landing(conn, landing, params, now)
    else
      kept
      |> touch(now)
      |> put_landing(conn, landing, params, now)
    end
  end

  defp new_visit?(%{"seen" => seen, "campaign" => current}, params, timeout, now)
       when is_integer(seen),
       do: now - seen > timeout or (params != %{} and campaign(params) != current)

  defp new_visit?(_visit, _params, _timeout, _now), do: true

  # The campaign a visit landed with, compared without keeping its params
  # twice, and still there when `fit/1` drops the landing's params.
  defp campaign(params) when params == %{}, do: nil
  defp campaign(params), do: :erlang.phash2(params)

  defp touch(%{"visit" => %{"seen" => seen} = visit} = kept, now) when now - seen >= @seen_step,
    do: Map.put(kept, "visit", %{visit | "seen" => now})

  defp touch(kept, _now), do: kept

  defp put_landing(kept, _conn, nil, _params, _now), do: kept

  defp put_landing(kept, %{method: method}, _landing, _params, _now) when method != "GET",
    do: kept

  defp put_landing(kept, conn, landing, params, now) do
    if landing?(kept, params, landing.attribution) do
      Map.put(kept, "landing", %{
        "path" => cut(conn.request_path),
        "at" => now,
        "params" => params,
        "referrer" => referrer(conn, landing.referrer)
      })
    else
      kept
    end
  end

  defp fit(kept) do
    cond do
      :erlang.external_size(kept) <= @max_kept -> kept
      kept["landing"]["params"] not in [nil, %{}] -> fit(put_in(kept, ["landing", "params"], %{}))
      Map.has_key?(kept, "headers") -> fit(Map.delete(kept, "headers"))
      true -> Map.delete(kept, "landing")
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
