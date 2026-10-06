defmodule PhoenixReplay.Capture.Browser do
  @moduledoc """
  Builds a recording's client context: the browser's viewport and tab from
  LiveView's connect params and event metadata, the user agent, and the
  request context `PhoenixReplay.Plug` keeps for the visit.

  PhoenixReplay's client module sends them when the host app passes its
  helpers to `LiveSocket`:

      import { replayParams, replayMetadata } from "phoenix_replay"

      const liveSocket = new LiveSocket("/live", Socket, {
        params: () => ({ _csrf_token: csrfToken, ...replayParams() }),
        metadata: replayMetadata
      })

  The connect params give the viewport and tab when the LiveView connects.
  While the page is recorded, `replayRecorder/1` sends the viewport as it
  changes, a resized window or a rotated phone, once it settles, and it is
  recorded as a `:viewport` event; see `viewport/1`. The metadata also adds
  the viewport to each click and key press as a `"_replay"` param, which
  catches changes when `replayRecorder/1` does not run. The host's
  `handle_event/3` sees the extra param; it is left out of recorded params.

  The last viewport seen is kept in the LiveView's process dictionary,
  since both the recorder's hooks and LiveComponent telemetry run there.
  """

  alias PhoenixReplay.Recording
  alias PhoenixReplay.Recording.Client
  alias PhoenixReplay.Recording.Client.Landing
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
  params, the `User-Agent` in its connect info, and the request context
  `PhoenixReplay.Plug` kept for the visit.
  """
  @spec build(map() | nil, String.t() | nil, map() | nil) :: Client.t()
  def build(connect_params, user_agent, kept) do
    replay = (connect_params || %{})["_replay"]
    viewport = parse(replay)
    Process.put(@key, viewport)
    kept = kept || %{}

    %Client{
      viewport: viewport,
      user_agent: user_agent,
      tab: tab(replay),
      navigated_from: navigated_from((connect_params || %{})["_live_referer"]),
      headers: Map.get(kept, "headers", %{}),
      landing: landing(kept["landing"])
    }
  end

  defp landing(%{"path" => path, "at" => at} = landing) do
    %Landing{
      path: path,
      at: at,
      params: Map.get(landing, "params", %{}),
      referrer: landing["referrer"]
    }
  end

  defp landing(_landing), do: nil

  @doc "The event name the browser sends viewport changes as, while it is recorded."
  @spec viewport_event() :: String.t()
  def viewport_event, do: "phx_replay:viewport"

  @doc """
  Records a `:viewport` event when the browser reports a viewport that
  differs from the last one seen: sent on its own as the window is resized
  or the phone rotated, or with a click or key press as a fallback.
  """
  @spec viewport(map()) :: :ok
  def viewport(params) do
    with %{} = viewport <- parse(params),
         true <- viewport != Process.get(@key) do
      Process.put(@key, viewport)
      Buffer.record(self(), :viewport, viewport)
    end

    :ok
  end

  @doc """
  Records a `:viewport` event when an event's params carry a viewport that
  differs from the last one seen, and returns the params without it.
  """
  @spec observe(map()) :: map()
  def observe(%{"_replay" => replay} = params) do
    :ok = viewport(replay)
    Map.delete(params, "_replay")
  end

  def observe(params), do: params

  defp dpr(dpr) when is_number(dpr) and dpr > 0 and dpr <= 10, do: dpr
  defp dpr(_dpr), do: 1

  defp tab(%{"tab" => tab}) when is_binary(tab) and byte_size(tab) in 1..@max_tab, do: tab
  defp tab(_replay), do: nil

  # The client sends "undefined" when there was no live navigation.
  defp navigated_from(url) when is_binary(url) and url not in ["", "undefined"], do: url
  defp navigated_from(_url), do: nil
end
