defmodule ExampleWeb.Features.ReplayTest do
  use PhoenixTest.Playwright.Case, async: false
  use ExampleWeb, :verified_routes

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
  test "realistic user session is recorded and replayable", %{conn: conn, config: config} do
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

    # --- Act 1: Browse and explore ---
    conn =
      conn
      |> visit(~p"/")
      # Interacting before the LiveView connects would drop the event.
      |> assert_has("body .phx-connected")
      |> assert_has("h1", text: "Tasks")

    # User looks around, clicks filters
    conn = conn |> click_button("Active") |> assert_has("button", text: "Active 2")
    Process.sleep(800)
    conn = conn |> click_button("Completed") |> assert_has("button", text: "Completed 1")
    Process.sleep(600)
    conn = conn |> click_button("All") |> assert_has("button", text: "All 3")
    Process.sleep(400)

    # Toggle a task
    conn = conn |> click_button("Toggle Review PR #42")
    Process.sleep(500)
    conn = conn |> assert_has("button", text: "Completed 2")

    # Undo it
    conn = conn |> click_button("Toggle Review PR #42")
    Process.sleep(300)
    conn = conn |> assert_has("button", text: "Completed 1")

    # --- Act 2: Create a task with realistic typing ---
    conn = conn |> click_link("New Task") |> assert_has("h2", text: "New Task")
    Process.sleep(600)

    # Type title slowly with a typo: "Shipt v2.0" → backspace → "Ship v2.0"
    conn = conn |> PhoenixTest.Playwright.type("#title", "Shipt", delay: 90)
    Process.sleep(300)
    conn = conn |> PhoenixTest.Playwright.press("#title", "Backspace")
    Process.sleep(150)
    conn = conn |> PhoenixTest.Playwright.press("#title", "Backspace")
    Process.sleep(100)
    conn = conn |> PhoenixTest.Playwright.type("#title", "p v2.0", delay: 75)
    Process.sleep(500)

    # Tab to description, type with a pause mid-thought
    conn = conn |> PhoenixTest.Playwright.type("#description", "Final releas", delay: 70)
    Process.sleep(900)
    conn = conn |> PhoenixTest.Playwright.type("#description", "e — ready to ship!", delay: 60)
    Process.sleep(400)

    # Change priority
    conn = conn |> select("Priority", option: "High")
    Process.sleep(300)

    # Submit
    conn = conn |> click_button("Create Task")
    conn = conn |> assert_has("p", text: "Ship v2.0")
    conn = conn |> assert_has("button", text: "All 4")
    Process.sleep(500)

    # --- Act 3: Edit a task ---
    conn = conn |> click_link("Edit Update dependencies")
    conn = conn |> assert_has("h2", text: "Edit Task")
    Process.sleep(400)

    # Clear field and type new title (like a human: End key, then backspace everything)
    conn = conn |> PhoenixTest.Playwright.press("#title", "End")
    Process.sleep(100)

    old_title = "Update dependencies"

    conn =
      Enum.reduce(1..String.length(old_title), conn, fn _, acc ->
        Process.sleep(40)
        PhoenixTest.Playwright.press(acc, "#title", "Backspace")
      end)

    Process.sleep(200)
    conn = conn |> PhoenixTest.Playwright.type("#title", "Update all deps", delay: 65)
    Process.sleep(300)
    conn = conn |> click_button("Save Changes")
    conn = conn |> assert_has("p", text: "Update all deps")
    Process.sleep(400)

    # --- Act 4: Delete a task ---
    conn = conn |> click_button("Delete Write documentation")
    conn = conn |> refute_has("p", text: "Write documentation")
    conn = conn |> assert_has("button", text: "All 3")
    Process.sleep(300)

    # --- Act 5: Final filter browse ---
    conn = conn |> click_button("Completed 1")
    Process.sleep(600)
    conn = conn |> click_button("All 3")
    Process.sleep(300)

    # Navigate away to finalize the recording
    conn = conn |> visit(~p"/replay") |> assert_has("body .phx-connected")
    conn = conn |> assert_has("h1", text: "Recordings")

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
    conn = conn |> visit(~p"/replay") |> assert_has("li", text: "ExampleWeb.TaskLive.Index")

    # Open it: the whole row links to the recording
    conn = conn |> click_link("ExampleWeb.TaskLive.Index")
    conn = conn |> assert_has("h1", text: "ExampleWeb.TaskLive.Index")

    # Player controls are present
    conn = conn |> assert_has("button[aria-label='Play']")
    conn = conn |> assert_has("#replay-scrubber[role='slider']")
    conn = conn |> assert_has("iframe#replay-frame")

    # Events panel shows our actions and the queries behind them
    conn = conn |> assert_has("button", text: "mount")
    conn = conn |> assert_has("button", text: "assigns")
    conn = conn |> assert_has("button", text: "GROUP BY")

    # Step forward through a few events
    conn = conn |> click_button("Next event")
    conn = conn |> click_button("Next event")
    conn = conn |> click_button("Next event")

    # Tabs and segmented controls send their button's value
    conn = conn |> PhoenixTest.Playwright.click("[role='tab']", "State")
    conn = conn |> assert_has("#replay-assigns")
    conn = conn |> PhoenixTest.Playwright.click("[role='tab']", "Events")
    conn = conn |> click_button("2×")
    conn = conn |> assert_has("button[aria-pressed='true']", text: "2×")

    # Play briefly, then pause
    conn = conn |> PhoenixTest.Playwright.click("button[aria-label='Play']")
    Process.sleep(1500)
    conn |> PhoenixTest.Playwright.click("button[aria-label='Pause']")
  end
end
