defmodule ExampleWeb.Features.TaskLiveTest do
  use PhoenixTest.Playwright.Case, async: false
  use ExampleWeb, :verified_routes

  alias Example.{Repo, Tasks.Task}

  setup do
    Repo.insert!(%Task{
      title: "Review PR #42",
      description: "Check the auth flow",
      priority: "high"
    })

    Repo.insert!(%Task{
      title: "Update deps",
      priority: "low",
      completed: true
    })

    Repo.insert!(%Task{
      title: "Write docs",
      priority: "medium"
    })

    :ok
  end

  test "lists tasks with correct counts", %{conn: conn} do
    conn
    |> visit(~p"/")
    |> assert_has("body .phx-connected")
    |> assert_has("h1", text: "Tasks")
    |> assert_has("button", text: "All 3")
    |> assert_has("button", text: "Active 2")
    |> assert_has("button", text: "Completed 1")
    |> assert_has("p", text: "Review PR #42")
    |> assert_has("p", text: "Write docs")
  end

  test "toggle task completion", %{conn: conn} do
    conn
    |> visit(~p"/")
    |> assert_has("body .phx-connected")
    |> click_button("Toggle Review PR #42")
    |> assert_has("button", text: "Active 1")
    |> assert_has("button", text: "Completed 2")
    |> click_button("Toggle Review PR #42")
    |> assert_has("button", text: "Active 2")
    |> assert_has("button", text: "Completed 1")
  end

  test "filter tasks", %{conn: conn} do
    conn
    |> visit(~p"/")
    |> assert_has("body .phx-connected")
    |> click_button("Active")
    |> assert_has("p", text: "Review PR #42")
    |> assert_has("p", text: "Write docs")
    |> refute_has("p", text: "Update deps")
    |> click_button("Completed")
    |> assert_has("p", text: "Update deps")
    |> refute_has("p", text: "Review PR #42")
    |> click_button("All")
    |> assert_has("p", text: "Review PR #42")
    |> assert_has("p", text: "Update deps")
    |> assert_has("p", text: "Write docs")
  end

  test "create a new task", %{conn: conn} do
    conn
    |> visit(~p"/")
    |> assert_has("body .phx-connected")
    |> click_link("New Task")
    |> assert_has("h2", text: "New Task")
    |> fill_in("Title", with: "Ship v2.0")
    |> fill_in("Description", with: "Final release")
    |> select("Priority", option: "High")
    |> click_button("Create Task")
    |> assert_has("p", text: "Ship v2.0")
    |> assert_has("button", text: "All 4")
  end

  test "edit an existing task", %{conn: conn} do
    conn
    |> visit(~p"/")
    |> assert_has("body .phx-connected")
    |> click_link("Edit Review PR #42")
    |> assert_has("h2", text: "Edit Task")
    |> fill_in("Title", with: "Review PR #43")
    |> click_button("Save Changes")
    |> assert_has("p", text: "Review PR #43")
    |> refute_has("p", text: "Review PR #42")
  end

  test "delete a task", %{conn: conn} do
    conn
    |> visit(~p"/")
    |> assert_has("body .phx-connected")
    |> assert_has("button", text: "All 3")
    |> click_button("Delete Write docs")
    |> refute_has("p", text: "Write docs")
    |> assert_has("button", text: "All 2")
  end

  @tag :capture_log
  test "a failed sync shows an error", %{conn: conn} do
    conn
    |> visit(~p"/")
    |> assert_has("body .phx-connected")
    |> click_button("Sync")
    |> assert_has("#flash-error", text: "Sync failed")
  end

  test "cancel modal returns to task list", %{conn: conn} do
    conn
    |> visit(~p"/")
    |> assert_has("body .phx-connected")
    |> click_link("New Task")
    |> assert_has("h2", text: "New Task")
    |> click_link("Cancel")
    |> refute_has("h2", text: "New Task")
    |> assert_has("h1", text: "Tasks")
  end
end
