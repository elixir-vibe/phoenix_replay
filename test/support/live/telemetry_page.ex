defmodule PhoenixReplay.Test.Live.TelemetryPage do
  @moduledoc """
  View that emits telemetry and logs from its own process and from a task,
  for collector tests.
  """

  use Phoenix.LiveView

  require Logger

  @doc "The event this view emits, with a 5 ms duration."
  @spec event() :: [atom()]
  def event, do: [:phoenix_replay_test, :work, :stop]

  @impl true
  def mount(_params, _session, socket), do: {:ok, assign(socket, done: 0)}

  @impl true
  def handle_event("work", %{"source" => source}, socket) do
    emit(source)
    {:noreply, update(socket, :done, &(&1 + 1))}
  end

  def handle_event("async", %{"source" => source}, socket) do
    {:noreply, start_async(socket, :work, fn -> emit(source) end)}
  end

  def handle_event("log", %{"level" => level, "message" => message}, socket) do
    Logger.log(String.to_existing_atom(level), message, source: "page")
    {:noreply, socket}
  end

  @impl true
  def handle_async(:work, {:ok, :ok}, socket), do: {:noreply, update(socket, :done, &(&1 + 1))}

  @impl true
  def render(assigns) do
    ~H"""
    <span id="done">{@done}</span>
    """
  end

  defp emit(source) do
    duration = System.convert_time_unit(5, :millisecond, :native)
    :telemetry.execute(event(), %{duration: duration}, %{source: source, password: "hunter2"})
  end
end
