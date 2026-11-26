defmodule ExampleWeb.Features.ReplayTest do
  # Paces every browser call, so the recording plays like a person using the app.
  use ExampleWeb.FeatureCase, async: false, launch_options: [slow_mo: 300]
  use ExampleWeb, :verified_routes
  use Fluffy.Assert

  import Fluffy
  import Fluffy.Locator
  import Fluffy.Locator.Roles
  import Fluffy.Playwright, only: [press_sequentially: 4]

  alias Example.{Repo, Tasks.Task}

  setup do
    config = PhoenixReplay.Config.load()
    PhoenixReplay.Catalog.clear(config)
    on_exit(fn -> PhoenixReplay.Catalog.clear(config) end)

    test = self()
    handler = {__MODULE__, :persisted}

    :telemetry.attach(
      handler,
      [:phoenix_replay, :recording, :persisted],
      fn _event, _measurements, %{id: id}, _config -> send(test, {:persisted, id}) end,
      nil
    )

    on_exit(fn -> :telemetry.detach(handler) end)

    %{config: config}
  end

  @doc """
  Simulates a realistic user session: browsing tasks, creating one with
  typos and corrections, toggling completion, filtering, editing, deleting.
  Then verifies the recording appears in the replay dashboard and plays back.

  Also serves as a demo recording — run with `mix test test/features/replay_test.exs`
  and open http://localhost:4005/replay to see the result.
  """
  test "realistic user session is recorded and replayable", %{conn: session, config: config} do
    # Seed some tasks so the list isn't empty
    Repo.insert!(%Task{
      title: "Review PR #42",
      description: "Check the auth flow",
      priority: "high"
    })

    Repo.insert!(%Task{title: "Update dependencies", priority: "low", completed: true})

    Repo.insert!(%Task{
      title: "Write documentation",
      description: "API reference",
      priority: "medium"
    })

    session
    # --- Act 1: Browse and explore ---
    |> visit(~p"/")
    |> assert_has(by_role(:heading, name: "Tasks"))
    # User looks around, clicks filters
    |> click(button("Active"))
    |> assert_has(button("Active 2"))
    |> pause(800)
    |> click(button("Completed"))
    |> assert_has(button("Completed 1"))
    |> pause(600)
    |> click(button("All"))
    |> assert_has(button("All 3"))
    # Toggle a task, then undo it
    |> click(button("Toggle Review PR #42"))
    |> assert_has(button("Completed 2"))
    |> click(button("Toggle Review PR #42"))
    |> assert_has(button("Completed 1"))
    # --- Act 2: Create a task with realistic typing ---
    |> click(link("New Task"))
    |> assert_has(by_role(:heading, name: "New Task"))
    |> pause(600)
    # Type title slowly with a typo: "Shipt v2.0" → backspace → "Ship v2.0"
    |> press_sequentially(by_label("Title"), "Shipt", delay: 90)
    |> press(by_label("Title"), "Backspace")
    |> press(by_label("Title"), "Backspace")
    |> press_sequentially(by_label("Title"), "p v2.0", delay: 75)
    # Tab to description, type with a pause mid-thought
    |> press_sequentially(by_label("Description"), "Final releas", delay: 70)
    |> pause(900)
    |> press_sequentially(by_label("Description"), "e — ready to ship!", delay: 60)
    |> select_option(by_label("Priority"), %{label: "High"})
    |> click(button("Create Task"))
    |> assert_has(by_text("Ship v2.0"))
    |> assert_has(button("All 4"))
    # --- Act 3: Edit a task: select the old title and type over it ---
    |> click(link("Edit Update dependencies"))
    |> assert_has(by_role(:heading, name: "Edit Task"))
    |> press(by_label("Title"), "ControlOrMeta+a")
    |> press_sequentially(by_label("Title"), "Update all deps", delay: 65)
    |> click(button("Save Changes"))
    |> assert_has(by_text("Update all deps"))
    # --- Act 4: Delete a task ---
    |> click(button("Delete Write documentation"))
    |> refute_has(by_text("Write documentation"))
    |> assert_has(button("All 3"))
    # --- Act 5: Final filter browse ---
    |> click(button("Completed 1"))
    |> pause(600)
    |> click(button("All 3"))
    # Navigate away to finalize the recording
    |> visit(~p"/replay")
    |> assert_has(by_role(:heading, name: "Recordings"))

    # --- Verify what was recorded ---
    assert_receive {:persisted, id}, 5_000
    {:ok, recording} = PhoenixReplay.Catalog.fetch(config, id)

    # Queries are recorded alongside the events that ran them, including
    # the stats component's query, which runs in an assign_async task
    assert Enum.any?(recording.events, &(&1.type == :telemetry))

    assert Enum.any?(recording.events, fn event ->
             event.type == :telemetry and event.data.summary =~ "GROUP BY"
           end)

    # Creating and completing tasks are marked, from Example.Tasks' telemetry
    marks =
      for event <- recording.events,
          PhoenixReplay.Recording.Event.mark?(event),
          do: event.data.summary

    assert Enum.any?(marks, &String.starts_with?(&1, "created "))
    assert "completed Review PR #42" in marks

    # The stats component's first async result is recorded as component
    # state before the user did anything. Later updates keep the previous
    # result while reloading, so only the first load proves it is recorded.
    loaded =
      Enum.find_index(recording.events, fn
        %{type: :component, data: %{assigns: %{stats: %{ok?: true}}}} -> true
        _event -> false
      end)

    assert loaded < Enum.find_index(recording.events, &(&1.type == :event))

    # --- Verify the recording is listed ---
    # The list keeps its place while sessions end, so it shows the session
    # saved since it opened once it is opened again.
    session
    |> visit(~p"/replay")
    |> assert_has(by_css("li") |> filter(has_text: "ExampleWeb.TaskLive.Index"))

    # Open it: the whole row links to the recording
    |> click(link("ExampleWeb.TaskLive.Index"))
    |> assert_has(by_role(:heading, name: "ExampleWeb.TaskLive.Index"))

    # Player controls are present
    |> assert_has(button("Play", exact: true))
    |> assert_has(by_css("#replay-scrubber[role='slider']"))
    |> assert_has(by_css("iframe#replay-frame"))

    # Events panel shows our actions and the queries behind them
    |> assert_has(button("mount") |> first())
    |> assert_has(button("assigns") |> first())
    |> assert_has(button("GROUP BY") |> first())

    # Step forward through a few events
    |> click(button("Next event"))
    |> click(button("Next event"))
    |> click(button("Next event"))

    # Tabs and segmented controls send their button's value
    |> click(by_role(:tab, name: "State"))
    |> assert_has(by_css("#replay-assigns"))
    |> click(by_role(:tab, name: "Events"))
    |> click(button("2×"))
    |> assert_has(button("2×", pressed: true))

    # Play briefly, then pause
    |> click(button("Play", exact: true))
    |> pause(1500)
    |> click(button("Pause", exact: true))
  end

  # A longer beat for the demo recording, on top of the module's slow_mo.
  defp pause(session, ms) do
    Process.sleep(ms)
    session
  end
end
