defmodule PhoenixReplay.Test.Sessions do
  @moduledoc """
  Starts recorded LiveViews in tests and awaits their finalization.

  `setup_sessions/1` starts a tracker fed by a telemetry handler for
  `PhoenixReplay.Telemetry`'s finalization events, which fire after a
  session leaves the buffer. Tests start recorded views with `live/3`,
  stop them with `stop/2`, and the tracker stops and awaits every remaining
  session on exit, so no test leaves buffered sessions for the next one.

  Waiting is message-driven; timeouts only bound a failure.
  """

  use GenServer

  import Phoenix.ConnTest, only: [get: 2]

  require Phoenix.LiveViewTest

  @endpoint PhoenixReplay.Test.Endpoint

  @events [
    [:phoenix_replay, :recording, :persisted],
    [:phoenix_replay, :recording, :discarded],
    [:phoenix_replay, :recording, :failed]
  ]

  @timeout 5_000

  @doc "ExUnit setup callback adding a `:sessions` tracker to the context."
  @spec setup_sessions(map()) :: %{sessions: pid()}
  def setup_sessions(context) do
    {:ok, tracker} = GenServer.start(__MODULE__, nil)
    handler = {__MODULE__, context.module, context.test}
    :ok = :telemetry.attach_many(handler, @events, &__MODULE__.handle_telemetry/4, tracker)

    ExUnit.Callbacks.on_exit(fn ->
      result = GenServer.call(tracker, :finish, @timeout)
      :telemetry.detach(handler)
      GenServer.stop(tracker)
      if result != :ok, do: raise("recorded sessions were not finalized: #{inspect(result)}")
    end)

    %{sessions: tracker}
  end

  @doc "Mounts a recorded LiveView and tracks its session. Returns the recording id too."
  @spec live(pid(), Plug.Conn.t(), String.t()) ::
          {:ok, struct(), String.t(), PhoenixReplay.Recording.id()}
  def live(tracker, conn, path) do
    {:ok, view, html} = Phoenix.LiveViewTest.live(conn, path)
    id = :sys.get_state(view.pid).socket.private.phoenix_replay.id
    :ok = GenServer.call(tracker, {:track, id, view.pid})
    {:ok, view, html, id}
  end

  @doc "Tracks the session of a view mounted another way, such as `live_isolated/3`."
  @spec track(pid(), struct()) :: PhoenixReplay.Recording.id()
  def track(tracker, view) do
    id = :sys.get_state(view.pid).socket.private.phoenix_replay.id
    :ok = GenServer.call(tracker, {:track, id, view.pid})
    id
  end

  @doc "Stops a tracked view and returns how its session was finalized."
  @spec stop(pid(), struct()) :: :persisted | :discarded | :failed
  def stop(tracker, view) do
    id = :sys.get_state(view.pid).socket.private.phoenix_replay.id
    GenServer.stop(view.pid)
    GenServer.call(tracker, {:await, id}, @timeout)
  end

  @doc "Awaits how a tracked session that ended on its own was finalized."
  @spec await(pid(), PhoenixReplay.Recording.id()) :: :persisted | :discarded | :failed
  def await(tracker, id), do: GenServer.call(tracker, {:await, id}, @timeout)

  @doc "Telemetry handler forwarding finalization events to the tracker."
  @spec handle_telemetry([atom()], map(), map(), pid()) :: :ok
  def handle_telemetry([:phoenix_replay, :recording, outcome], _measures, %{id: id}, tracker) do
    send(tracker, {:finalized, id, outcome})
    :ok
  end

  @impl true
  def init(nil), do: {:ok, %{tracked: %{}, outcomes: %{}, waiters: []}}

  @impl true
  def handle_call({:track, id, pid}, _from, state),
    do: {:reply, :ok, put_in(state.tracked[id], pid)}

  def handle_call({:await, id}, from, state),
    do: {:noreply, reply_ready(state, [{from, {:one, id}}])}

  def handle_call(:finish, from, state) do
    for {id, pid} <- state.tracked,
        not Map.has_key?(state.outcomes, id),
        do: Process.exit(pid, :kill)

    {:noreply, reply_ready(state, [{from, {:all, Map.keys(state.tracked)}}])}
  end

  @impl true
  def handle_info({:finalized, id, outcome}, state) do
    {:noreply, reply_ready(put_in(state.outcomes[id], outcome), [])}
  end

  defp reply_ready(state, new_waiters) do
    {ready, waiting} =
      Enum.split_with(state.waiters ++ new_waiters, fn {_from, wanted} ->
        wanted |> ids() |> Enum.all?(&Map.has_key?(state.outcomes, &1))
      end)

    for {from, wanted} <- ready, do: GenServer.reply(from, reply(wanted, state.outcomes))
    %{state | waiters: waiting}
  end

  defp ids({:one, id}), do: [id]
  defp ids({:all, ids}), do: ids

  defp reply({:one, id}, outcomes), do: Map.fetch!(outcomes, id)
  defp reply({:all, _ids}, _outcomes), do: :ok
end
