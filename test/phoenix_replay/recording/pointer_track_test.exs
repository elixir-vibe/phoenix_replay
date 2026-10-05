defmodule PhoenixReplay.Recording.PointerTrackTest do
  use ExUnit.Case, async: true

  alias PhoenixReplay.Recording
  alias PhoenixReplay.Recording.{Event, PointerTrack}

  test "takes pointer batches out of a recording and times their samples" do
    batch = fn at, data ->
      %Event{
        at: at,
        type: :pointer,
        data: Map.merge(%{moves: [], presses: [], scrolls: []}, data)
      }
    end

    mount = %Event{at: 0, type: :mount, data: %{assigns: %{}}}
    click = %Event{at: 1_500, type: :event, data: %{name: "save", params: %{}}}

    recording = %Recording{
      id: "r",
      view: V,
      connected_at: 0,
      events: [
        mount,
        # Arrived at 1 000, its samples spanning the 800 ms before.
        batch.(1_000, %{span: 800, moves: [0, 1, 1, 0, 400, 2, 2, 0], scrolls: [100, 0, 50]}),
        click,
        batch.(2_000, %{
          span: 500,
          presses: [[300, 0, 2, 2, 0, 0, nil, 0, 0]],
          moves: [0, 3, 3, 0]
        })
      ]
    }

    assert {%Recording{events: [^mount, ^click]}, track} = PointerTrack.split(recording)
    assert track.moves == [[200, 1, 1, 0], [600, 2, 2, 0], [1_500, 3, 3, 0]]
    assert track.presses == [[1_800, 0, 2, 2, 0, 0, nil, 0, 0]]
    assert track.scrolls == [[300, 0, 50]]
    assert PointerTrack.any?(track)
    refute PointerTrack.any?(elem(PointerTrack.split(%{recording | events: [mount]}), 1))
  end
end
