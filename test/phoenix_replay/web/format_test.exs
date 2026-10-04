defmodule PhoenixReplay.Web.FormatTest do
  use ExUnit.Case, async: true

  alias PhoenixReplay.Web.Format

  test "formats times" do
    assert Format.clock(65_432) == "1:05"
    assert Format.duration(12_000) == "12s"
    assert Format.duration(184_000) == "3m 4s"
    assert Format.timestamp(0) == "1970-01-01 00:00:00"
  end

  test "says how long ago a time was" do
    now = 1_800_000_000_000
    assert Format.relative(now - 12_000, now) == "12 s ago"
    assert Format.relative(now - 5 * 60_000, now) == "5 min ago"
    assert Format.relative(now - 11 * 3_600_000, now) == "11 h ago"
    assert Format.relative(now - 30 * 3_600_000, now) == "Yesterday"
    assert Format.relative(now - 6 * 86_400_000, now) == "Jan 9"
    assert Format.relative(now + 5_000, now) == "0 s ago"
  end

  test "formats durations and counts" do
    assert Format.milliseconds(0.4213) == "0.42 ms"
    assert Format.milliseconds(42.6) == "43 ms"
    assert Format.milliseconds(1_540) == "1.5 s"

    assert Format.count(1, "error") == "1 error"
    assert Format.count(0, "error") == "0 errors"
    assert Format.count(2, "match", "matches") == "2 matches"
  end

  test "labels viewports, devices and referers" do
    assert Format.viewport(%{width: 390, height: 844, dpr: 3}) == "390 × 844 @3x"
    assert Format.viewport(%{width: 1440, height: 900, dpr: 1}) == "1440 × 900"
    assert Format.viewport(%{width: 412, height: 915, dpr: 2.625}) == "412 × 915 @2.6x"

    assert Format.device(
             "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) Version/18.0 Mobile/15E148 Safari/604.1"
           ) == "Safari on iOS"

    assert Format.device(
             "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) Chrome/141.0 Safari/537.36"
           ) == "Chrome on macOS"

    assert Format.device("curl/8.0") == nil
    assert Format.device(nil) == nil

    assert Format.path_of("http://www.example.com/tasks?filter=all") == "/tasks?filter=all"
  end

  test "labels campaigns and referrers" do
    assert Format.campaign(%{"utm_source" => "google", "utm_campaign" => "spring"}) ==
             "google / spring"

    assert Format.campaign(%{"ref" => "x"}) == nil

    assert Format.referrer_host("https://news.ycombinator.com/item?id=1") ==
             "news.ycombinator.com"

    assert Format.referrer_host("not a url") == nil
    assert Format.referrer_host(nil) == nil
  end
end
