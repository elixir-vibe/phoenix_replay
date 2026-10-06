defmodule PhoenixReplay.Recording.ClientTest do
  use ExUnit.Case, async: true

  alias PhoenixReplay.Recording.Client
  alias PhoenixReplay.Recording.Client.Landing
  alias PhoenixReplay.Recording.Traffic

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

    assert Client.traffic(
             landing.(
               %{"utm_source" => "google", "utm_medium" => "cpc", "utm_campaign" => "spring"},
               nil
             )
           ) == %Traffic{source: "google", medium: "cpc", campaign: "spring"}

    assert Client.traffic(landing.(%{}, "https://news.ycombinator.com/item?id=1")) ==
             %Traffic{source: "news.ycombinator.com", medium: "referral"}

    assert Client.traffic(landing.(%{"ref" => "x"}, nil)) ==
             %Traffic{source: "(direct)", medium: "(none)"}

    # Without a kept landing, where the visit came from is unknown.
    assert Client.traffic(%Client{}) == %Traffic{}
    assert Client.referrer_host("not a url") == nil
  end

  test "tells the kind of device and the browser" do
    assert Client.device_type(%{width: 390, height: 844, dpr: 3}) == "phone"
    assert Client.device_type(%{width: 820, height: 1180, dpr: 2}) == "tablet"
    assert Client.device_type(%{width: 1440, height: 900, dpr: 1}) == "desktop"
    assert Client.device_type(nil) == nil

    assert Client.browser_family(
             "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 " <>
               "(KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1"
           ) == "Mobile Safari"

    assert Client.browser_family("") == nil
  end

  test "stores viewports compactly" do
    for viewport <- [%{width: 390, height: 844, dpr: 3}, %{width: 412, height: 915, dpr: 2.625}] do
      assert viewport |> Client.encode_viewport() |> Client.decode_viewport() == viewport
    end

    assert Client.encode_viewport(nil) == nil
    assert Client.decode_viewport("garbage") == nil
    assert Client.decode_viewport(nil) == nil
  end

  test "tells a viewport's orientation as CSS does" do
    assert Client.orientation(%{width: 390, height: 844}) == :portrait
    assert Client.orientation(%{width: 844, height: 390}) == :landscape
    # As CSS has it, a square viewport is portrait.
    assert Client.orientation(%{width: 600, height: 600}) == :portrait
  end
end
