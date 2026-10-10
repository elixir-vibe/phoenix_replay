defmodule Mix.Tasks.PhoenixReplay.TraceTasksTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureIO

  alias PhoenixReplay.Recording.Event
  alias PhoenixReplay.Storage
  alias PhoenixReplay.Test.Fixtures

  setup do
    recording = Fixtures.counter_recording(id: "listed")
    error = %Event{at: 1_500, type: :log, data: %{level: :error, message: "boom", metadata: %{}}}

    :ok =
      Storage.save(Fixtures.storage(), %{
        recording
        | events: List.insert_at(recording.events, 4, error)
      })

    on_exit(fn -> Storage.delete(Fixtures.storage(), "listed") end)
    :ok
  end

  test "lists saved recordings as Trace finds them" do
    output =
      capture_io(fn -> Mix.Tasks.PhoenixReplay.List.run(["--errors", "--text", "listed"]) end)

    assert output =~ ~s(id: "listed")
    assert output =~ "error_count: 1"

    assert capture_io(fn -> Mix.Tasks.PhoenixReplay.List.run(["--text", "nothing-like-it"]) end) =~
             "[]"

    assert_raise Mix.Error, ~r/:within must be one of/, fn ->
      Mix.Tasks.PhoenixReplay.List.run(["--within", "2h"])
    end
  end

  test "prints the events of each recording of a visit" do
    for {id, at} <- [{"visit-a", 1}, {"visit-b", 2}] do
      recording = Fixtures.counter_recording(id: id, connected_at: at)

      :ok =
        Storage.save(Fixtures.storage(), %{
          recording
          | client: %PhoenixReplay.Recording.Client{visit: "visit-shown"}
        })
    end

    on_exit(fn -> for id <- ~w(visit-a visit-b), do: Storage.delete(Fixtures.storage(), id) end)
    output = capture_io(fn -> Mix.Tasks.PhoenixReplay.Show.run(["visit-shown"]) end)

    assert output =~ ~s(recording: "visit-a")
    assert output =~ ~s(recording: "visit-b")
    assert :binary.match(output, "visit-a") < :binary.match(output, "visit-b")

    assert_raise Mix.Error, ~r/No recording or visit/, fn ->
      Mix.Tasks.PhoenixReplay.Show.run(["nothing"])
    end
  end

  test "prints a recording's events, or the view at one" do
    events = capture_io(fn -> Mix.Tasks.PhoenixReplay.Show.run(["listed"]) end)
    assert events =~ ~s(label: "[error] boom")
    assert events =~ "error?: true"

    state = capture_io(fn -> Mix.Tasks.PhoenixReplay.Show.run(["listed", "--at", "3"]) end)
    assert state =~ "assigns: %{count: 1}"
    assert state =~ ~s(path: "count")

    assert_raise Mix.Error, "No recording or visit missing", fn ->
      Mix.Tasks.PhoenixReplay.Show.run(["missing"])
    end
  end
end
