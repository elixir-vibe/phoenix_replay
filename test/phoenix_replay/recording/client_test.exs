defmodule PhoenixReplay.Recording.ClientTest do
  use ExUnit.Case, async: true

  alias PhoenixReplay.Recording.Client
  alias PhoenixReplay.Recording.Client.Landing

  test "names the browser and system of a user agent" do
    assert Client.device(
             "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 " <>
               "(KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1"
           ) == "Mobile Safari 18 on iOS"

    # Browsers that name another in their user agent are told apart.
    assert Client.device(
             "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) " <>
               "Chrome/141.0.0.0 Safari/537.36 Edg/141.0.0.0"
           ) == "Edge 141 on Windows"

    assert Client.device(
             "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 " <>
               "(KHTML, like Gecko) CriOS/141.0 Mobile/15E148 Safari/604.1"
           ) == "Chrome Mobile iOS 141 on iOS"

    assert Client.device("curl/8.0") == "curl 8"
    assert Client.device("") == nil
    assert Client.device(nil) == nil
  end

  test "names where a visit came from" do
    landing = fn params, referrer ->
      %Client{landing: %Landing{path: "/", at: 0, params: params, referrer: referrer}}
    end

    assert Client.source(landing.(%{"utm_source" => "google", "utm_medium" => "cpc"}, nil)) ==
             "google / cpc"

    assert Client.source(landing.(%{}, "https://news.ycombinator.com/item?id=1")) ==
             "news.ycombinator.com"

    assert Client.source(landing.(%{"ref" => "x"}, nil)) == nil
    assert Client.source(%Client{}) == nil
    assert Client.referrer_host("not a url") == nil
  end

  test "stores viewports compactly" do
    for viewport <- [%{width: 390, height: 844, dpr: 3}, %{width: 412, height: 915, dpr: 2.625}] do
      assert viewport |> Client.encode_viewport() |> Client.decode_viewport() == viewport
    end

    assert Client.encode_viewport(nil) == nil
    assert Client.decode_viewport("garbage") == nil
    assert Client.decode_viewport(nil) == nil
  end
end
