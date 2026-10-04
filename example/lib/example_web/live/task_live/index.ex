defmodule ExampleWeb.TaskLive.Index do
  use ExampleWeb, :live_view

  require Logger

  alias Example.Tasks

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket), do: Tasks.subscribe()

    {:ok,
     socket
     |> assign(:page_title, "Tasks")
     |> assign(:filter, "all")
     |> assign(:tasks, Tasks.list_tasks())}
  end

  @impl true
  def handle_params(params, _url, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :new, _params) do
    assign(socket, :form, to_form(%{"title" => "", "description" => "", "priority" => "medium"}))
  end

  defp apply_action(socket, :edit, %{"id" => id}) do
    task = Tasks.get_task(id)

    if task do
      assign(
        socket,
        :form,
        to_form(%{
          "id" => task.id,
          "title" => task.title,
          "description" => task.description || "",
          "priority" => task.priority
        })
      )
    else
      push_navigate(socket, to: ~p"/")
    end
  end

  defp apply_action(socket, :index, _params) do
    assign(socket, :form, nil)
  end

  @impl true
  def handle_event("toggle", %{"id" => id}, socket) do
    Tasks.toggle_task(id)
    {:noreply, socket}
  end

  def handle_event("delete", %{"id" => id}, socket) do
    Tasks.delete_task(id)
    {:noreply, socket}
  end

  # Shows how a failure looks in a replay: the failed query and the error
  # log are recorded, and the session is kept by `keep: [errors: true]`.
  def handle_event("sync", _params, socket) do
    case Tasks.sync() do
      :ok ->
        {:noreply, socket}

      {:error, message} ->
        Logger.error("Sync failed: #{message}")
        {:noreply, put_flash(socket, :error, "Sync failed")}
    end
  end

  def handle_event("filter", %{"filter" => filter}, socket) do
    {:noreply, assign(socket, :filter, filter)}
  end

  def handle_event("save", %{"title" => _} = params, socket) do
    case socket.assigns.live_action do
      :new ->
        case Tasks.create_task(params) do
          {:ok, task} -> Logger.info("Created task #{task.id}")
          {:error, _changeset} -> Logger.warning("Could not create a task")
        end

        {:noreply, push_patch(socket, to: ~p"/")}

      :edit ->
        Tasks.update_task(params["task_id"], params)
        {:noreply, push_patch(socket, to: ~p"/")}
    end
  end

  def handle_event("validate", params, socket) do
    task =
      case socket.assigns.live_action do
        :edit -> %Example.Tasks.Task{id: params["task_id"]}
        _ -> %Example.Tasks.Task{}
      end

    changeset = Example.Tasks.Task.changeset(task, params)
    {:noreply, assign(socket, :form, to_form(changeset, action: :validate))}
  end

  @impl true
  def handle_info({event, _task}, socket)
      when event in [:task_created, :task_updated, :task_deleted] do
    {:noreply, assign(socket, :tasks, Tasks.list_tasks())}
  end

  defp filtered_tasks(tasks, "all"), do: tasks
  defp filtered_tasks(tasks, "active"), do: Enum.reject(tasks, & &1.completed)
  defp filtered_tasks(tasks, "done"), do: Enum.filter(tasks, & &1.completed)

  defp filter_count(tasks, "all"), do: length(tasks)
  defp filter_count(tasks, "active"), do: Enum.count(tasks, &(!&1.completed))
  defp filter_count(tasks, "done"), do: Enum.count(tasks, & &1.completed)

  defp priority_classes("high"), do: "bg-red-50 text-red-700 ring-red-600/20"
  defp priority_classes("medium"), do: "bg-amber-50 text-amber-700 ring-amber-600/20"
  defp priority_classes("low"), do: "bg-green-50 text-green-700 ring-green-600/20"
end
