defmodule PhoenixReplay.Web.AssetsTest do
  use ExUnit.Case, async: true

  import Phoenix.ConnTest

  alias PhoenixReplay.Web.Assets

  @endpoint PhoenixReplay.Test.Endpoint

  test "serves hashed bundle files with immutable caching" do
    for {kind, type} <- [js: "text/javascript", css: "text/css"] do
      name = Assets.file_name(kind)
      assert name =~ ~r/^dashboard-[0-9a-f]{8}\.(js|css)$/

      conn = get(build_conn(), "/replay/assets/#{name}")
      assert conn.status == 200
      assert [content_type] = Plug.Conn.get_resp_header(conn, "content-type")
      assert content_type =~ type

      assert Plug.Conn.get_resp_header(conn, "cache-control") == [
               "public, max-age=31536000, immutable"
             ]
    end
  end

  test "serves the fonts the stylesheet refers to, next to it" do
    css = get(build_conn(), "/replay/assets/#{Assets.file_name(:css)}").resp_body
    fonts = Regex.scan(~r/url\(([^)]+\.woff2)\)/, css, capture: :all_but_first)
    assert length(fonts) == 2

    for [font] <- fonts do
      conn = get(build_conn(), "/replay/assets/#{font}")
      assert conn.status == 200
      assert Plug.Conn.get_resp_header(conn, "content-type") == ["font/woff2"]
    end
  end

  test "serves JavaScript through the host's forgery protection" do
    # ConnTest skips CSRF protection by default; browsers do not.
    conn =
      build_conn()
      |> Plug.Conn.put_private(:plug_skip_csrf_protection, false)
      |> get("/replay/assets/#{Assets.file_name(:js)}")

    assert conn.status == 200
  end

  test "serves the host's Phoenix and LiveView clients by version" do
    for app <- [:phoenix, :phoenix_live_view] do
      name = Assets.file_name(app)
      assert name == "#{app}-#{Application.spec(app, :vsn)}.js"

      conn = get(build_conn(), "/replay/assets/#{name}")
      assert conn.status == 200
      assert conn.resp_body == File.read!(Path.join(:code.priv_dir(app), "static/#{app}.min.js"))
    end
  end

  test "returns 404 for anything else" do
    assert get(build_conn(), "/replay/assets/dashboard.js").status == 404
  end
end
