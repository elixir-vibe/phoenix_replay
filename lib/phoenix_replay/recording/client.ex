defmodule PhoenixReplay.Recording.Client do
  @moduledoc """
  The browser and the visit a recording came from, when the browser told
  PhoenixReplay (see `PhoenixReplay.Capture.Browser`):

    * `:viewport` — `%{width: integer, height: integer, dpr: number}` when
      the LiveView connected; later changes are `:viewport` events
    * `:user_agent` — the `User-Agent` header, when the endpoint's socket
      lists `:user_agent` in its `:connect_info`
    * `:tab` — an id of the browser tab, shared by the tab's sessions
    * `:navigated_from` — the URL of the LiveView that live-navigated here
    * `:headers` — request headers listed in the `:client` config, kept by
      `PhoenixReplay.Plug`
    * `:landing` — the visit's first request, when the `:client` config asks for it;
      see `PhoenixReplay.Recording.Client.Landing`

  Its functions describe the device, named from its user agent with
  `UAParser`, and where the visit came from.
  """

  alias PhoenixReplay.Recording
  alias PhoenixReplay.Recording.Client.Landing
  alias PhoenixReplay.Recording.Traffic

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

  @default_viewport %{width: 1280, height: 800, dpr: 1}
  # The settings a viewport may carry, and the media features they are.
  @media_features [
    color_scheme: "prefers-color-scheme",
    reduced_motion: "prefers-reduced-motion",
    contrast: "prefers-contrast",
    pointer: "pointer",
    hover: "hover"
  ]

  @doc """
  A viewport's media settings as the CSS media features they are, for the
  replay to apply to the replayed page's media rules: `%{"pointer" =>
  "coarse", "prefers-color-scheme" => "dark", ...}`, with those the browser
  did not report left out.
  """
  @spec media(PhoenixReplay.Recording.viewport() | nil) :: %{String.t() => String.t()}
  def media(nil), do: %{}

  def media(viewport) do
    for {setting, feature} <- @media_features, Map.has_key?(viewport, setting), into: %{} do
      {feature, media_value(setting, Map.fetch!(viewport, setting))}
    end
  end

  defp media_value(:reduced_motion, true), do: "reduce"
  defp media_value(:reduced_motion, false), do: "no-preference"
  defp media_value(_setting, value), do: value |> Atom.to_string() |> String.replace("_", "-")

  @doc """
  A viewport's orientation as CSS's `orientation` media feature tells it:
  portrait when it is at least as tall as it is wide.
  """
  @spec orientation(%{
          :width => pos_integer(),
          :height => pos_integer(),
          optional(atom()) => term()
        }) ::
          :portrait | :landscape
  def orientation(%{width: width, height: height}) when height >= width, do: :portrait
  def orientation(_viewport), do: :landscape

  @doc "The viewport a recording without one is shown at, such as in an export."
  @spec default_viewport() :: PhoenixReplay.Recording.viewport()
  def default_viewport, do: @default_viewport

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
  The browser in a user agent, without its version, such as `"Mobile
  Safari"`, or `nil` when it is not recognized.
  """
  @spec browser_family(String.t() | nil) :: String.t() | nil
  def browser_family(nil), do: nil

  def browser_family(user_agent) do
    case UAParser.parse(user_agent) do
      %{family: family} when family not in [nil, "Other"] -> family
      _unknown -> nil
    end
  end

  @typedoc "The kind of device a session ran on, by its viewport's width; see `device_type/1`."
  @type device_type :: String.t()

  @device_types ~w(phone tablet desktop)

  @doc "The kinds of device `device_type/1` tells apart."
  @spec device_types() :: [device_type()]
  def device_types, do: @device_types

  @doc """
  The kind of device a viewport belongs to, by its width in CSS pixels:
  `"phone"` below 640, `"tablet"` below 1024, `"desktop"` otherwise, or
  `nil` without a viewport.
  """
  @spec device_type(PhoenixReplay.Recording.viewport() | nil) :: device_type() | nil
  def device_type(nil), do: nil
  def device_type(%{width: width}) when width < 640, do: "phone"
  def device_type(%{width: width}) when width < 1024, do: "tablet"
  def device_type(%{width: _width}), do: "desktop"

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
  Where the visit came from, as Google Analytics tells it; see
  `PhoenixReplay.Recording.Traffic`.
  """
  @spec traffic(t()) :: Traffic.t()
  def traffic(%__MODULE__{landing: %Landing{params: params, referrer: referrer}}) do
    host = referrer_host(referrer)

    %Traffic{
      source: param(params, "utm_source") || host || "(direct)",
      medium: param(params, "utm_medium") || if(host, do: "referral", else: "(none)"),
      campaign: param(params, "utm_campaign")
    }
  end

  def traffic(%__MODULE__{}), do: %Traffic{}

  defp param(params, key) do
    case params[key] do
      value when is_binary(value) and value != "" -> value
      _none -> nil
    end
  end

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
