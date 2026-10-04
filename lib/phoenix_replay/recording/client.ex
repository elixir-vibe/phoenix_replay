defmodule PhoenixReplay.Recording.Client do
  @moduledoc """
  Describes the browser and the visit a recording's `client` context
  holds: the device, named from its user agent with `UAParser`, and where
  the visit came from.
  """

  alias PhoenixReplay.Recording

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

  @campaign_keys ~w(utm_source utm_medium utm_campaign)

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
  @spec source(Recording.client()) :: String.t() | nil
  def source(%{landing: %{params: params, referrer: referrer}}),
    do: campaign(params) || referrer_host(referrer)

  def source(_client), do: nil

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
