defmodule PhoenixReplay.Session.TailSamplingTest do
  use ExUnit.Case, async: true

  alias PhoenixReplay.Recording.Event
  alias PhoenixReplay.Session.TailSampling
  alias PhoenixReplay.Test.Fixtures

  @keep %{rate: 1.0, errors: false, slower_than: nil}

  defp with_event(recording, type, data),
    do: %{recording | events: [%Event{at: 9_000, type: type, data: data} | recording.events]}

  defp query(duration, error \\ nil),
    do: %{
      event: [:repo, :query],
      summary: "SELECT 1",
      measurements: %{duration: duration},
      metadata: %{},
      error: error
    }

  test "keeps the sampled share of interactive sessions" do
    recording = Fixtures.counter_recording()

    assert TailSampling.decide(recording, @keep, 0.99) == :keep
    assert TailSampling.decide(recording, %{@keep | rate: 0.5}, 0.5) == :keep
    assert TailSampling.decide(recording, %{@keep | rate: 0.5}, 0.51) == {:discard, :not_sampled}
    assert TailSampling.decide(recording, %{@keep | rate: 0.0}, 0.0) == {:discard, :not_sampled}
  end

  test "counts a second navigation as interaction" do
    params = %Event{at: 1, type: :params, data: %{params: %{}, uri: "/"}}
    quiet = Fixtures.counter_recording(clicks: 0)

    assert TailSampling.decide(%{quiet | events: [params | quiet.events]}, @keep, 0.0) ==
             {:discard, :not_interactive}

    assert TailSampling.decide(%{quiet | events: [params, params | quiet.events]}, @keep, 0.0) ==
             :keep
  end

  test "decides the same incrementally, and never turns back from keeping" do
    recording = Fixtures.counter_recording(clicks: 2)
    {head, tail} = Enum.split(recording.events, 3)
    keep = %{@keep | rate: 0.5}

    observation = TailSampling.observe(TailSampling.new(), head, keep)
    assert TailSampling.decision(observation, keep, 0.1) == :keep

    assert observation |> TailSampling.observe(tail, keep) |> TailSampling.decision(keep, 0.1) ==
             TailSampling.decide(recording, keep, 0.1)
  end

  test "discards sessions without interaction" do
    assert TailSampling.decide(Fixtures.counter_recording(clicks: 0), @keep, 0.0) ==
             {:discard, :not_interactive}
  end

  test "always keeps sessions with errors when asked" do
    keep = %{@keep | rate: 0.0, errors: true}
    quiet = Fixtures.counter_recording(clicks: 0)

    assert TailSampling.decide(with_event(quiet, :exit, %{reason: "boom"}), keep, 1.0) == :keep

    assert TailSampling.decide(with_event(quiet, :telemetry, query(1, "timeout")), keep, 1.0) ==
             :keep

    assert TailSampling.decide(
             with_event(quiet, :log, %{level: :error, message: "", metadata: %{}}),
             keep,
             1.0
           ) ==
             :keep

    assert TailSampling.decide(
             with_event(quiet, :log, %{level: :warning, message: "", metadata: %{}}),
             keep,
             1.0
           ) ==
             {:discard, :not_interactive}

    assert TailSampling.decide(with_event(quiet, :exit, %{reason: "boom"}), @keep, 1.0) ==
             {:discard, :not_interactive}
  end

  test "always keeps sessions with slow events when asked" do
    keep = %{@keep | rate: 0.0, slower_than: 100}
    recording = Fixtures.counter_recording()

    assert TailSampling.decide(with_event(recording, :telemetry, query(100)), keep, 1.0) == :keep

    assert TailSampling.decide(with_event(recording, :telemetry, query(99.9)), keep, 1.0) ==
             {:discard, :not_sampled}
  end
end
