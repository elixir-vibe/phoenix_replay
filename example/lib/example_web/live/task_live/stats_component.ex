defmodule ExampleWeb.TaskLive.StatsComponent do
  @moduledoc """
  Open tasks by priority, loaded with `assign_async/3`.

  The query runs in a task, so PhoenixReplay records it in the LiveView's
  session, and the loaded result is recorded as component state.
  """

  use ExampleWeb, :live_component

  alias Example.Tasks

  @priorities ~w(high medium low)

  @impl true
  def update(assigns, socket) do
    {:ok,
     socket
     |> assign(assigns)
     |> assign_async(:stats, fn -> {:ok, %{stats: Tasks.open_by_priority()}} end)}
  end

  @impl true
  def render(assigns) do
    assigns = assign(assigns, :priorities, @priorities)

    ~H"""
    <p id={@id} class="mb-6 flex gap-4 text-xs text-gray-500">
      <.async_result :let={stats} assign={@stats}>
        <:loading>Counting open tasks…</:loading>
        <:failed>Could not count open tasks</:failed>
        <span :for={priority <- @priorities}>
          {String.capitalize(priority)}
          <span class="font-medium text-gray-900 tabular-nums">{Map.get(stats, priority, 0)}</span>
        </span>
        <span>open</span>
      </.async_result>
    </p>
    """
  end
end
