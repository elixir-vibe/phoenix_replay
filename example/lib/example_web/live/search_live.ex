defmodule ExampleWeb.SearchLive do
  @moduledoc """
  Finds tasks in the browser alone: the server never hears about the query.

  A script filters the list as you type (see `assets/js/client_search.ts`)
  and reports the query with `replayState`. The replay cannot run that
  script, so `replay_render/1` narrows the list from the recorded query.
  """

  use ExampleWeb, :live_view
  @behaviour PhoenixReplay.Replay.View

  alias Example.Tasks

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     assign(socket,
       page_title: "Find tasks",
       tasks: Tasks.list_tasks(),
       query: nil,
       replay?: false
     )}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="mx-auto max-w-2xl px-4 py-10">
      <h1 class="mb-6 text-2xl font-semibold tracking-tight">Find tasks</h1>
      <%!-- Live, the browser owns the box; the replay fills it on every seek. --%>
      <div
        id="client-search"
        phx-hook={!@replay? && "ClientSearch"}
        phx-update={!@replay? && "ignore"}
      >
        <input
          type="search"
          value={@query}
          placeholder="Type to filter, in your browser…"
          aria-label="Find tasks"
          data-phx-replay-ignore
          class="mb-4 h-9 w-full rounded-md border border-gray-200 px-3 text-sm placeholder:text-gray-400 focus:border-gray-400 focus:outline-none"
        />
      </div>
      <ul id="task-titles" class="divide-y divide-gray-100 rounded-lg border border-gray-200">
        <li :for={task <- found(@tasks, @query)} data-title={task.title} class="px-4 py-2.5 text-sm">
          {task.title}
        </li>
      </ul>
    </div>
    """
  end

  # In a replay the filtering script does not run: the query it reported
  # is in `@phoenix_replay_state`.
  @impl PhoenixReplay.Replay.View
  def replay_render(assigns) do
    assigns
    |> Phoenix.Component.assign(
      query: get_in(assigns.phoenix_replay_state, ["search", "query"]),
      replay?: true
    )
    |> render()
  end

  # Live, the browser filters; only the replay filters here.
  defp found(tasks, query) when query in [nil, ""], do: tasks

  defp found(tasks, query) do
    query = String.downcase(query)
    Enum.filter(tasks, &String.contains?(String.downcase(&1.title), query))
  end
end
