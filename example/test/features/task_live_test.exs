defmodule ExampleWeb.Features.TaskLiveTest do
  use ExampleWeb.FeatureCase, async: false
  use ExampleWeb, :verified_routes
  use Fluffy.Assert

  import Fluffy
  import Fluffy.Locator
  import Fluffy.Locator.Roles

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

  test "lists tasks with correct counts", %{conn: session} do
    session
    |> visit(~p"/")
    |> assert_has(by_role(:heading, name: "Tasks"))
    |> assert_has(button("All 3"))
    |> assert_has(button("Active 2"))
    |> assert_has(button("Completed 1"))
    |> assert_has(by_text("Review PR #42"))
    |> assert_has(by_text("Write docs"))
  end

  test "toggle task completion", %{conn: session} do
    session
    |> visit(~p"/")
    |> click(button("Toggle Review PR #42"))
    |> assert_has(button("Active 1"))
    |> assert_has(button("Completed 2"))
    |> click(button("Toggle Review PR #42"))
    |> assert_has(button("Active 2"))
    |> assert_has(button("Completed 1"))
  end

  test "filter tasks", %{conn: session} do
    session
    |> visit(~p"/")
    |> click(button("Active"))
    |> assert_has(by_text("Review PR #42"))
    |> assert_has(by_text("Write docs"))
    |> refute_has(by_text("Update deps"))
    |> click(button("Completed"))
    |> assert_has(by_text("Update deps"))
    |> refute_has(by_text("Review PR #42"))
    |> click(button("All"))
    |> assert_has(by_text("Review PR #42"))
    |> assert_has(by_text("Update deps"))
    |> assert_has(by_text("Write docs"))
  end

  test "create a new task", %{conn: session} do
    session
    |> visit(~p"/")
    |> click(link("New Task"))
    |> assert_has(by_role(:heading, name: "New Task"))
    |> fill(by_label("Title"), "Ship v2.0")
    |> fill(by_label("Description"), "Final release")
    |> select_option(by_label("Priority"), %{label: "High"})
    |> click(button("Create Task"))
    |> assert_has(by_text("Ship v2.0"))
    |> assert_has(button("All 4"))
  end

  test "edit an existing task", %{conn: session} do
    session
    |> visit(~p"/")
    |> click(link("Edit Review PR #42"))
    |> assert_has(by_role(:heading, name: "Edit Task"))
    |> fill(by_label("Title"), "Review PR #43")
    |> click(button("Save Changes"))
    |> assert_has(by_text("Review PR #43"))
    |> refute_has(by_text("Review PR #42"))
  end

  test "delete a task", %{conn: session} do
    session
    |> visit(~p"/")
    |> assert_has(button("All 3"))
    |> click(button("Delete Write docs"))
    |> refute_has(by_text("Write docs"))
    |> assert_has(button("All 2"))
  end

  @tag :capture_log
  test "a failed sync shows an error", %{conn: session} do
    session
    |> visit(~p"/")
    |> click(button("Sync"))
    |> assert_has(by_css("#flash-error") |> filter(has_text: "Sync failed"))
  end

  test "cancel modal returns to task list", %{conn: session} do
    session
    |> visit(~p"/")
    |> click(link("New Task"))
    |> assert_has(by_role(:heading, name: "New Task"))
    |> click(link("Cancel"))
    |> refute_has(by_role(:heading, name: "New Task"))
    |> assert_has(by_role(:heading, name: "Tasks"))
  end
end
