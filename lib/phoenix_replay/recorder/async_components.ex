defmodule PhoenixReplay.Recorder.AsyncComponents do
  @moduledoc """
  Records LiveComponent state changed by async results.

  LiveView emits no telemetry when a `start_async/3`, `assign_async/3` or
  `stream_async/4` result is applied to a LiveComponent, and the render
  that follows clears the component's change tracking, so
  `PhoenixReplay.Recorder.Components` never sees that state.

  This is a workaround until LiveView emits
  `[:phoenix, :live_component, :handle_async, :stop]`, proposed in
  https://github.com/phoenixframework/phoenix_live_view/pull/4463. Once it
  does, `PhoenixReplay.Recorder.Components` records async results from that
  event, every component render is explained, and this module stops firing.

  A component render that no recorded event explains is taken to be an
  async result. A supervised task then reads the component's assigns with
  `Phoenix.LiveView.Debug.live_components/1`, which cannot be called from
  the LiveView process itself, and records them as a `:component` event.
  The snapshot reflects the component once the LiveView handles the
  request, which may include changes from messages queued behind the
  render, and its offset is the time it is recorded.
  """

  alias PhoenixReplay.Recorder.Buffer

  @unreplayable [:__changed__, :myself, :flash]

  @doc """
  Notes that the next render of the component is caused by an event that
  was recorded. Called from the LiveView process.

  LiveView renders a component after an event exactly when the event left
  its socket changed, so a note is set only then and is always consumed
  by that render.
  """
  @spec explain(Phoenix.LiveView.Socket.t()) :: :ok
  def explain(%{assigns: %{myself: %{cid: cid}, __changed__: changed}})
      when map_size(changed) > 0 do
    Process.put({__MODULE__, cid}, true)
    :ok
  end

  def explain(_socket), do: :ok

  @doc """
  Handles a component render in the LiveView process, snapshotting the
  component when no recorded event explains it.
  """
  @spec rendered(module(), term(), pos_integer()) :: :ok
  def rendered(module, id, cid) do
    cond do
      Process.delete({__MODULE__, cid}) -> :ok
      Buffer.session(self()) == :error -> :ok
      true -> snapshot_later(self(), module, id, cid)
    end
  end

  @doc "Records the current assigns of the component `cid` rendered by `pid`."
  @spec snapshot(pid(), module(), term(), pos_integer()) :: :ok | :error
  def snapshot(pid, module, id, cid) do
    with {:ok, components} <- Phoenix.LiveView.Debug.live_components(pid),
         %{assigns: assigns} <- Enum.find(components, &(&1.cid == cid)),
         {:ok, _id, config} <- Buffer.session(pid) do
      assigns = assigns |> Map.drop(@unreplayable) |> config.sanitizer.sanitize_assigns()
      Buffer.record(pid, :component, %{module: module, id: id, assigns: assigns})
      :ok
    else
      _gone -> :error
    end
  end

  defp snapshot_later(pid, module, id, cid) do
    {:ok, _task} =
      Task.Supervisor.start_child(PhoenixReplay.TaskSupervisor, __MODULE__, :snapshot, [
        pid,
        module,
        id,
        cid
      ])

    :ok
  end
end
