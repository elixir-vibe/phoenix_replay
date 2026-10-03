defmodule PhoenixReplay.CollectorTest do
  use ExUnit.Case, async: true

  alias PhoenixReplay.Collector

  test "milliseconds/1 converts durations and *_time, drops timestamps, keeps other numbers" do
    native = System.convert_time_unit(1_500, :microsecond, :native)

    assert Collector.milliseconds(%{
             duration: native,
             query_time: native,
             monotonic_time: 1,
             system_time: 2,
             rows: 3,
             label: "x"
           }) == %{duration: 1.5, query_time: 1.5, rows: 3}
  end

  test "name/1 joins an event name with dots" do
    assert Collector.name([:my_app, :repo, :query]) == "my_app.repo.query"
  end

  test "error/2 and result_error/1 describe failures on one line" do
    assert Collector.error(:error, %RuntimeError{message: "boom\nmore"}) ==
             "** (RuntimeError) boom"

    assert Collector.result_error({:error, %RuntimeError{message: "boom"}}) == "boom"
    assert Collector.result_error({:error, :timeout}) == ":timeout"
    assert Collector.result_error({:ok, []}) == nil
  end
end
