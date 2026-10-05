defmodule PhoenixReplay.Recording.Client do
  @moduledoc """
  The browser and the visit a recording came from, when the browser told
  PhoenixReplay (see `PhoenixReplay.Capture.Client`):

    * `:viewport` — `%{width: integer, height: integer, dpr: number}` when
      the LiveView connected; later changes are `:viewport` events
    * `:user_agent` — the `User-Agent` header, when the endpoint's socket
      lists `:user_agent` in its `:connect_info`
    * `:tab` — an id of the browser tab, shared by the tab's sessions
    * `:navigated_from` — the URL of the LiveView that live-navigated here
    * `:headers` — request headers listed in `:context`, kept by
      `PhoenixReplay.Plug`
    * `:landing` — the visit's first request, when `:context` asks for it;
      see `PhoenixReplay.Recording.Client.Landing`

  Its functions describe the device, named from its user agent with
  `UAParser`, and where the visit came from.
  """

  alias PhoenixReplay.Recording
  alias PhoenixReplay.Recording.Client.Landing

  @type t :: %__MODULE__{
          viewport: Recording.viewport() | nil,
          user_agent: String.t() | nil,
          tab: String.t() | nil,
          navigated_from: String.t() | nil,
          headers: %{String.t() => String.t()},
          landing: Landing.t() | nil
        }

  defstruct [:viewport, :user_agent, :tab, :navigated_from, :landing, headers: %{}]

  @campaign_keys ~w(utm_source utm_medium utm_campaign)

  @doc """
  Brings a client context stored by an earlier version up to date: plain
  maps before 0.6, which named `:navigated_from` `:referer`.
  """
  @spec upgrade(t() | map()) :: t()
  def upgrade(%__MODULE__{landing: landing} = client),
    do: %{client | landing: upgrade_landing(landing)}

  def upgrade(%{} = client) do
    fields = client |> Map.delete(:__struct__) |> Map.put_new(:navigated_from, client[:referer])
    upgrade(struct(__MODULE__, fields))
  end

  defp upgrade_landing(%Landing{} = landing), do: landing
  defp upgrade_landing(%{} = landing), do: struct(Landing, landing)
  defp upgrade_landing(nil), do: nil

  @doc """
  Names the browser, with its major version, and the system in a user
  agent, such as `"Mobile Safari 18 on iOS"`, or returns `nil` when neither
  is recognized.
  """
  @spec device(String.t() | nil) :: String.t() | nil
  def device(nil), do: nil

  def device(user_agent) do
    agent = UAParser.parse(user_agent)

    case {browser(agent), agent.os.family} do
      {nil, nil} -> nil
      {browser, nil} -> browser
      {nil, system} -> system
      {browser, system} -> "#{browser} on #{system}"
    end
  end

  defp browser(%{family: nil}), do: nil
  defp browser(%{family: "Other"}), do: nil
  defp browser(%{family: family, version: %{major: nil}}), do: family
  defp browser(%{family: family, version: %{major: major}}), do: "#{family} #{major}"
  defp browser(%{family: family}), do: family

  @doc """
  Describes a landing's campaign as `"google / cpc / spring_sale"`, from
  its UTM source, medium and campaign, or returns `nil` without them.
  """
  @spec campaign(map()) :: String.t() | nil
  def campaign(params) do
    case Enum.flat_map(@campaign_keys, &List.wrap(params[&1])) do
      [] -> nil
      parts -> Enum.join(parts, " / ")
    end
  end

  @doc "The host of a referrer URL, such as `\"news.ycombinator.com\"`, or `nil`."
  @spec referrer_host(String.t() | nil) :: String.t() | nil
  def referrer_host(nil), do: nil

  def referrer_host(url) do
    case URI.parse(url) do
      %URI{host: host} when is_binary(host) and host != "" -> host
      _other -> nil
    end
  end

  @doc """
  Where the visit came from: its landing's campaign, or else the host of
  the site that referred it. `nil` for direct visits and without
  `PhoenixReplay.Plug`.
  """
  @spec source(t()) :: String.t() | nil
  def source(%__MODULE__{landing: %Landing{params: params, referrer: referrer}}),
    do: campaign(params) || referrer_host(referrer)

  def source(%__MODULE__{}), do: nil

  @doc """
  Writes a viewport as `"390x844@3"`, compact for storing alongside a
  summary, or `nil`.
  """
  @spec encode_viewport(Recording.viewport() | nil) :: String.t() | nil
  def encode_viewport(nil), do: nil
  def encode_viewport(%{width: width, height: height, dpr: dpr}), do: "#{width}x#{height}@#{dpr}"

  @doc "Reads a viewport written by `encode_viewport/1`, or `nil`."
  @spec decode_viewport(String.t() | nil) :: Recording.viewport() | nil
  def decode_viewport(encoded) when is_binary(encoded) do
    with [size, dpr] <- String.split(encoded, "@"),
         [width, height] <- String.split(size, "x"),
         {width, ""} <- Integer.parse(width),
         {height, ""} <- Integer.parse(height),
         {dpr, ""} <- Float.parse(dpr) do
      %{width: width, height: height, dpr: if(dpr == trunc(dpr), do: trunc(dpr), else: dpr)}
    else
      _invalid -> nil
    end
  end

  def decode_viewport(_encoded), do: nil
end
