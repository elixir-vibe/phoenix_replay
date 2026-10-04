defmodule PhoenixReplay.Capture.LiveComponents do
  @moduledoc """
  Records LiveComponent state from LiveView's telemetry events.

  LiveComponents have no `on_mount` hook, but LiveView emits
  `[:phoenix, :live_component, :update | :handle_event, :stop]` and
  `[:phoenix, :live_component, :destroyed]` from the LiveView process with
  the component's socket. The handlers attached here run in that process,
  find its session in `PhoenixReplay.Session.Buffer`, and record:

    * `:event` — `%{name: String.t(), params: map, target: {module, id}}`,
      an event handled by a component, which the view's own hooks never see
    * `:component` — `%{module: module, id: term, assigns: map}`, the
      component assigns changed by an update or event
    * `:component_destroyed` — `%{module: module, id: term}`

  LiveView does not yet emit telemetry for async results applied to a
  component; `PhoenixReplay.Capture.AsyncResults` covers them until it
  does.

  Components of LiveViews that are not recorded cost one ETS lookup per
  event. Assigns go through the session's `PhoenixReplay.Sanitizer`.

  `:telemetry` detaches a handler that raises, which would stop component
  recording for the whole application, so the handlers match metadata
  loosely and ignore shapes they do not expect.
  """

  alias PhoenixReplay.Capture.{AsyncResults, Client}
  alias PhoenixReplay.Session.Buffer

  @handler __MODULE__
  @unreplayable [:myself, :flash]

  @events [
    [:phoenix, :live_component, :handle_event, :start],
    [:phoenix, :live_component, :update, :stop],
    [:phoenix, :live_component, :handle_event, :stop],
    [:phoenix, :live_component, :destroyed],
    # Proposed in https://github.com/phoenixframework/phoenix_live_view/pull/4463.
    # Until LiveView emits it, AsyncResults records async results instead.
    [:phoenix, :live_component, :handle_async, :stop],
    [:phoenix, :live_view, :render, :stop]
  ]

  @doc "Attaches the telemetry handlers. Called by `PhoenixReplay.Capture.Handlers`."
  @spec attach() :: :ok | {:error, :already_exists}
  def attach, do: :telemetry.attach_many(@handler, @events, &__MODULE__.handle_event/4, nil)

  @doc "Detaches the telemetry handlers, if attached."
  @spec detach() :: :ok
  def detach do
    _result = :telemetry.detach(@handler)
    :ok
  end

  @doc "Handles a LiveComponent telemetry event in the LiveView process."
  @spec handle_event([atom()], map(), map(), nil) :: :ok
  def handle_event(
        [:phoenix, :live_component, :handle_event, :start],
        _measures,
        %{component: module, socket: %{assigns: %{id: id}}, event: name, params: params},
        nil
      )
      when is_map(params) do
    case Buffer.session(self()) do
      {:ok, _id, config} ->
        params = config.sanitizer.sanitize_params(Client.observe(params))
        record(:event, %{name: name, params: params, target: {module, id}})

      :error ->
        :ok
    end
  end

  def handle_event(
        [:phoenix, :live_component, :update, :stop],
        _measures,
        %{component: module, sockets: sockets},
        nil
      )
      when is_list(sockets) do
    Enum.each(sockets, &record_changes(module, &1))
  end

  def handle_event(
        [:phoenix, :live_component, callback, :stop],
        _measures,
        %{component: module, socket: socket},
        nil
      )
      when callback in [:handle_event, :handle_async] do
    record_changes(module, socket)
    AsyncResults.explain(socket)
  end

  def handle_event(
        [:phoenix, :live_view, :render, :stop],
        _measures,
        %{component: module, id: id, cid: cid},
        nil
      )
      when is_integer(cid) do
    AsyncResults.rendered(module, id, cid)
  end

  def handle_event(
        [:phoenix, :live_component, :destroyed],
        _measures,
        %{component: module, socket: %{assigns: %{id: id}}},
        nil
      ) do
    record(:component_destroyed, %{module: module, id: id})
  end

  def handle_event(_event, _measures, _metadata, nil), do: :ok

  defp record_changes(module, %{assigns: %{id: id, __changed__: changed} = assigns})
       when map_size(changed) > 0 do
    with {:ok, _id, config} <- Buffer.session(self()),
         changes when map_size(changes) > 0 <- sanitized_changes(assigns, changed, config) do
      record(:component, %{module: module, id: id, assigns: changes})
    else
      _nothing -> :ok
    end
  end

  defp record_changes(_module, _socket), do: :ok

  defp sanitized_changes(assigns, changed, config) do
    assigns
    |> Map.take(Map.keys(changed))
    |> Map.drop(@unreplayable)
    |> config.sanitizer.sanitize_assigns()
  end

  defp record(type, data) do
    Buffer.record(self(), type, data)
    :ok
  end
end
