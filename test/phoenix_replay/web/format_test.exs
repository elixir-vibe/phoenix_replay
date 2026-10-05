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

    assert Format.path_of("http://www.example.com/tasks?filter=all") == "/tasks?filter=all"
  end
end
