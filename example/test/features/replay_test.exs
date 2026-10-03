defmodule ExampleWeb.Features.ReplayTest do
  use PhoenixTest.Playwright.Case, async: false
  use ExampleWeb, :verified_routes

  alias Example.{Repo, Tasks.Task}

  setup do
    config = PhoenixReplay.Config.load()
    PhoenixReplay.Recordings.clear(config)
    on_exit(fn -> PhoenixReplay.Recordings.clear(config) end)

    :ok
  end

  @doc """
  Simulates a realistic user session: browsing tasks, creating one with
  typos and corrections, toggling completion, filtering, editing, deleting.
  Then verifies the recording appears in the replay dashboard and plays back.

  Also serves as a demo recording — run with `mix test test/features/replay_test.exs`
  and open http://localhost:4005/replay to see the result.
  """
  test "realistic user session is recorded and replayable", %{conn: conn} do
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
    conn = conn |> visit(~p"/replay")
    conn = conn |> assert_has("h1", text: "PhoenixReplay")

    # --- Verify the recording exists ---
    conn = conn |> assert_has("li", text: "ExampleWeb.TaskLive.Index")

    # Open it
    conn = conn |> click_link("Open")
    conn = conn |> assert_has("h1", text: "ExampleWeb.TaskLive.Index")

    # Player controls are present
    conn = conn |> assert_has("button[aria-label='Play']")
    conn = conn |> assert_has("#replay-scrubber[role='slider']")
    conn = conn |> assert_has("iframe#replay-frame")

    # Events panel shows our actions
    conn = conn |> assert_has("button", text: "mount")
    conn = conn |> assert_has("button", text: "assigns")

    # Step forward through a few events
    conn = conn |> click_button("Next event")
    conn = conn |> click_button("Next event")
    conn = conn |> click_button("Next event")

    # Play briefly, then pause
    conn = conn |> PhoenixTest.Playwright.click("button[aria-label='Play']")
    Process.sleep(1500)
    conn |> PhoenixTest.Playwright.click("button[aria-label='Pause']")
  end
end
