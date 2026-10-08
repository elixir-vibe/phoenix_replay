defmodule PhoenixReplay.Test.Live.HaltingHook do
  @moduledoc """
  An app's `on_mount` hook that handles `"reset"` and halts, placed before
  `PhoenixReplay.Recorder`, as an app hook may be.
  """

  import Phoenix.Component, only: [assign: 3]
  import Phoenix.LiveView, only: [attach_hook: 4]

  def on_mount(:default, _params, _session, socket),
    do: {:cont, attach_hook(socket, :reset, :handle_event, &handle_event/3)}

  defp handle_event("reset", _params, socket), do: {:halt, assign(socket, :count, 0)}
  defp handle_event(_event, _params, socket), do: {:cont, socket}
end
