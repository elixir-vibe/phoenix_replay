defmodule Example.Tasks do
  @moduledoc """
  Task management context backed by Ecto + SQLite.
  """

  import Ecto.Query
  alias Example.Repo
  alias Example.Tasks.Task

  def list_tasks do
    Task |> order_by(desc: :inserted_at) |> Repo.all()
  end

  def get_task(id), do: Repo.get(Task, id)

  @doc "Pretends to sync with a remote service, whose table does not exist."
  def sync do
    case Repo.query("SELECT id FROM remote_tasks") do
      {:ok, _result} -> :ok
      {:error, error} -> {:error, Exception.message(error)}
    end
  end

  @doc "Counts open tasks by priority."
  def open_by_priority do
    Task
    |> where([t], not t.completed)
    |> group_by([t], t.priority)
    |> select([t], {t.priority, count(t.id)})
    |> Repo.all()
    |> Map.new()
  end

  def create_task(attrs) do
    %Task{}
    |> Task.changeset(attrs)
    |> Repo.insert()
    |> tap(fn
      {:ok, task} -> broadcast({:task_created, task})
      _ -> :ok
    end)
  end

  def update_task(id, attrs) do
    case get_task(id) do
      nil ->
        {:error, :not_found}

      task ->
        task
        |> Task.changeset(attrs)
        |> Repo.update()
        |> tap(fn
          {:ok, task} -> broadcast({:task_updated, task})
          _ -> :ok
        end)
    end
  end

  def toggle_task(id) do
    case get_task(id) do
      nil ->
        :error

      task ->
        task
        |> Task.changeset(%{"completed" => !task.completed})
        |> Repo.update()
        |> tap(fn
          {:ok, task} -> broadcast({:task_updated, task})
          _ -> :ok
        end)
    end
  end

  def delete_task(id) do
    case get_task(id) do
      nil -> :error
      task -> Repo.delete(task) |> tap(fn {:ok, task} -> broadcast({:task_deleted, task}) end)
    end
  end

  def subscribe do
    Phoenix.PubSub.subscribe(Example.PubSub, "tasks")
  end

  defp broadcast(message) do
    Phoenix.PubSub.broadcast(Example.PubSub, "tasks", message)
  end
end
