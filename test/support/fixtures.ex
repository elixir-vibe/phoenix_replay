defmodule PhoenixReplay.Test.Fixtures do
  @moduledoc "Builders for recordings used across tests."

  alias PhoenixReplay.Recording
  alias PhoenixReplay.Recording.Event

  @doc "Builds a recording of `PhoenixReplay.Test.Live.Counter` clicked `clicks` times."
  @spec counter_recording(keyword()) :: Recording.t()
  def counter_recording(opts \\ []) do
    clicks = Keyword.get(opts, :clicks, 2)

    events =
      Enum.flat_map(1..clicks//1, fn count ->
        [
          %Event{at: count * 1000, type: :event, data: %{name: "inc", params: %{}}},
          %Event{at: count * 1000 + 1, type: :render, data: %{assigns: %{count: count}}}
        ]
      end)

    %Recording{
      id: Keyword.get_lazy(opts, :id, &Recording.generate_id/0),
      view: PhoenixReplay.Test.Live.Counter,
      url: "http://localhost/counter",
      connected_at: Keyword.get(opts, :connected_at, System.system_time(:millisecond)),
      events:
        [
          %Event{at: 0, type: :mount, data: %{assigns: %{}}},
          %Event{at: 5, type: :render, data: %{assigns: %{count: 0}}}
        ] ++ events
    }
  end

  @doc "Returns the storage configured for the test environment."
  @spec storage() :: PhoenixReplay.Storage.t()
  def storage, do: PhoenixReplay.Config.load().storage
end
