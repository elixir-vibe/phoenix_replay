defmodule PhoenixReplay.Capture.Viewport do
  @moduledoc """
  Reads the browser's viewport and tab from LiveView's connect params and
  event metadata.

  PhoenixReplay's client module sends them when the host app passes its
  helpers to `LiveSocket`:

      import { replayParams, replayMetadata } from "phoenix_replay"

      const liveSocket = new LiveSocket("/live", Socket, {
        params: () => ({ _csrf_token: csrfToken, ...replayParams() }),
        metadata: replayMetadata
      })

  The connect params give the viewport and tab when the LiveView connects.
  The metadata adds the viewport to each click and key press as a
  `"_replay"` param, so a resize is recorded, as a `:viewport` event, with
  the user's next interaction. The host's `handle_event/3` sees the extra
  param; it is left out of recorded params.

  The last viewport seen is kept in the LiveView's process dictionary,
  since both the recorder's hooks and LiveComponent telemetry run there.
  """

  alias PhoenixReplay.Recording
  alias PhoenixReplay.Session.Buffer

  @key {__MODULE__, :viewport}
  @max_tab 64

  @doc "Parses a viewport sent by the client, or returns `nil`."
  @spec parse(term()) :: Recording.viewport() | nil
  def parse(%{"width" => width, "height" => height} = viewport)
      when is_integer(width) and is_integer(height) and width in 1..20_000 and
             height in 1..20_000 do
    %{width: width, height: height, dpr: dpr(viewport["dpr"])}
  end

  def parse(_viewport), do: nil

  @doc """
  Returns the client context of a connecting LiveView, from its connect
  params and the `User-Agent` in its connect info.
  """
  @spec client(map() | nil, String.t() | nil) :: Recording.client()
  def client(connect_params, user_agent) do
    replay = (connect_params || %{})["_replay"]
    viewport = parse(replay)
    Process.put(@key, viewport)

    %{
      viewport: viewport,
      user_agent: user_agent,
      tab: tab(replay),
      referer: referer((connect_params || %{})["_live_referer"])
    }
  end

  @doc """
  Records a `:viewport` event when an event's params carry a viewport that
  differs from the last one seen, and returns the params without it.
  """
  @spec observe(map()) :: map()
  def observe(%{"_replay" => replay} = params) do
    with %{} = viewport <- parse(replay),
         true <- viewport != Process.get(@key) do
      Process.put(@key, viewport)
      Buffer.record(self(), :viewport, viewport)
    end

    Map.delete(params, "_replay")
  end

  def observe(params), do: params

  defp dpr(dpr) when is_number(dpr) and dpr > 0 and dpr <= 10, do: dpr
  defp dpr(_dpr), do: 1

  defp tab(%{"tab" => tab}) when is_binary(tab) and byte_size(tab) in 1..@max_tab, do: tab
  defp tab(_replay), do: nil

  # The client sends "undefined" when there was no live navigation.
  defp referer(referer) when is_binary(referer) and referer not in ["", "undefined"],
    do: referer

  defp referer(_referer), do: nil
end
