defmodule PhoenixReplay.PlugTest do
  # Reads :client from the application environment, which tests change.
  use ExUnit.Case, async: false

  import Phoenix.ConnTest
  import Phoenix.LiveViewTest
  import Plug.Conn, only: [get_session: 2, put_req_header: 3]

  alias PhoenixReplay.Session.Buffer
  alias PhoenixReplay.Storage
  alias PhoenixReplay.Test.{Fixtures, Sessions}

  @endpoint PhoenixReplay.Test.Endpoint

  setup context do
    on_exit(fn ->
      Application.delete_env(:phoenix_replay, :client)
      Storage.clear(Fixtures.storage())
    end)

    Sessions.setup_sessions(context)
  end

  defp configure(context), do: Application.put_env(:phoenix_replay, :client, context)

  defp request(path, headers \\ [], session \\ %{}, method \\ :get) do
    conn = Plug.Test.init_test_session(build_conn(method, path), session)

    headers
    |> Enum.reduce(conn, fn {name, value}, acc -> put_req_header(acc, name, value) end)
    |> PhoenixReplay.Plug.call([])
  end

  defp kept(conn), do: get_session(conn, "phoenix_replay")

  test "keeps nothing without :client" do
    conn = request("/?utm_source=x", [{"accept-language", "en"}])

    assert kept(conn) == nil
    refute conn.private[:plug_session_info]
  end

  test "keeps the allowed headers of the latest request" do
    configure(headers: ["accept-language", "cf-ipcountry"])

    conn = request("/", [{"accept-language", "en-US"}, {"x-other", "1"}])
    assert kept(conn) == %{"headers" => %{"accept-language" => "en-US"}}

    long = String.duplicate("é", 300)
    conn = request("/", [{"cf-ipcountry", long}], %{"phoenix_replay" => kept(conn)})
    assert kept(conn)["headers"] == %{"cf-ipcountry" => String.duplicate("é", 256)}
  end

  test "keeps a crafted link from overflowing the session cookie" do
    configure(headers: ["accept-language"], landing: [params: [:utm, :click_ids]])
    long = String.duplicate("x", 300)

    query =
      Enum.map_join(
        ~w(utm_source utm_medium utm_campaign utm_term utm_content gclid),
        "&",
        &"#{&1}=#{long}"
      )

    conn =
      request("/" <> String.duplicate("p", 2_000) <> "?" <> query, [{"accept-language", long}])

    kept = kept(conn)

    assert :erlang.external_size(kept) <= 1_024
    assert String.length(kept["landing"]["path"]) == 256
    # The campaign params went first, so the landing itself is kept.
    assert kept["landing"]["params"] == %{}
  end

  test "keeps the first landing of the visit" do
    configure(landing: [params: [:utm]])

    conn =
      request("/pricing?utm_source=google&utm_medium=cpc&other=1", [
        {"referer", "https://www.google.com/search?q=secret"}
      ])

    assert %{
             "path" => "/pricing",
             "params" => %{"utm_source" => "google", "utm_medium" => "cpc"},
             "referrer" => "https://www.google.com/search",
             "at" => at
           } = kept(conn)["landing"]

    assert is_integer(at)

    # An unchanged context leaves the conn, and so the session cookie, alone.
    later =
      Plug.Test.init_test_session(build_conn(:get, "/?utm_source=newsletter"), %{
        "phoenix_replay" => kept(conn)
      })

    assert PhoenixReplay.Plug.call(later, []) == later
  end

  test "replaces the landing with the latest campaign when attribution is :last" do
    configure(landing: [params: [:utm], attribution: :last])
    first = request("/?utm_source=google")

    untracked = request("/about", [], %{"phoenix_replay" => kept(first)})
    assert kept(untracked)["landing"]["params"] == %{"utm_source" => "google"}

    campaign = request("/?utm_source=newsletter", [], %{"phoenix_replay" => kept(first)})
    assert kept(campaign)["landing"]["params"] == %{"utm_source" => "newsletter"}
  end

  test "keeps the full referrer only on request, and lands only on GET" do
    configure(landing: [referrer: :full])
    conn = request("/", [{"referer", "https://example.com/a?b=c"}])
    assert kept(conn)["landing"]["referrer"] == "https://example.com/a?b=c"

    configure(landing: [referrer: false])
    assert kept(request("/", [{"referer", "https://example.com/"}]))["landing"]["referrer"] == nil

    assert kept(request("/", [], %{}, :post)) == nil
  end

  test "recordings carry the visit's context", %{sessions: sessions} do
    configure(headers: ["accept-language"], landing: [params: [:utm]])

    conn =
      build_conn()
      |> put_req_header("accept-language", "de-DE")
      |> get("/counter?utm_source=news&utm_campaign=launch")

    {:ok, view, _html} = live(conn)
    id = Sessions.track(sessions, view)

    assert {:ok, %{client: client, session: session}} = Buffer.fetch(id)
    assert client.headers == %{"accept-language" => "de-DE"}

    assert %{path: "/counter", params: %{"utm_source" => "news", "utm_campaign" => "launch"}} =
             client.landing

    refute Map.has_key?(session, "phoenix_replay")
  end
end
