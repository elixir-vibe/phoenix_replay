defmodule PhoenixReplay.Web.Format do
  @moduledoc """
  Formats times, durations, devices and visit details for the dashboard.

  Plain functions returning strings, so components only lay things out.
  """

  @doc "Formats an offset as `m:ss`."
  @spec clock(non_neg_integer()) :: String.t()
  def clock(ms) do
    seconds = div(ms, 1000)

    "#{div(seconds, 60)}:#{seconds |> rem(60) |> Integer.to_string() |> String.pad_leading(2, "0")}"
  end

  @doc "Formats a duration as `12s` or `3m 4s`."
  @spec duration(non_neg_integer()) :: String.t()
  def duration(ms) do
    seconds = div(ms, 1000)

    case div(seconds, 60) do
      0 -> "#{seconds}s"
      minutes -> "#{minutes}m #{rem(seconds, 60)}s"
    end
  end

  @doc "Formats a Unix millisecond timestamp as UTC `YYYY-MM-DD HH:MM:SS`."
  @spec timestamp(integer()) :: String.t()
  def timestamp(unix_ms) do
    unix_ms |> DateTime.from_unix!(:millisecond) |> Calendar.strftime("%Y-%m-%d %H:%M:%S")
  end

  @doc """
  Describes how long before `now` a Unix millisecond timestamp was, such as
  `"12 s ago"`, `"5 min ago"`, `"11 h ago"` or `"Yesterday"`. Older times
  are dates, such as `"Sep 28"`.
  """
  @spec relative(integer(), integer()) :: String.t()
  def relative(unix_ms, now) do
    seconds = max(div(now - unix_ms, 1000), 0)

    cond do
      seconds < 60 -> "#{seconds} s ago"
      seconds < 3600 -> "#{div(seconds, 60)} min ago"
      seconds < 86_400 -> "#{div(seconds, 3600)} h ago"
      seconds < 172_800 -> "Yesterday"
      true -> unix_ms |> DateTime.from_unix!(:millisecond) |> Calendar.strftime("%b %-d")
    end
  end

  @doc "Formats a duration in milliseconds as `0.42 ms`, `12 ms` or `1.5 s`."
  @spec milliseconds(number()) :: String.t()
  def milliseconds(ms) when ms < 10, do: "#{:erlang.float_to_binary(ms / 1, decimals: 2)} ms"
  def milliseconds(ms) when ms < 1_000, do: "#{round(ms)} ms"
  def milliseconds(ms), do: "#{:erlang.float_to_binary(ms / 1_000, decimals: 1)} s"

  @doc """
  Counts things in words, such as `"1 error"` or `"3 errors"`.

  `plural` defaults to `singular` with an `s`.
  """
  @spec count(non_neg_integer(), String.t(), String.t() | nil) :: String.t()
  def count(count, singular, plural \\ nil)
  def count(1, singular, _plural), do: "1 #{singular}"
  def count(count, singular, plural), do: "#{count} #{plural || singular <> "s"}"

  @doc "Describes a viewport as `390 × 844 @3x`."
  @spec viewport(PhoenixReplay.Recording.viewport()) :: String.t()
  def viewport(%{width: width, height: height, dpr: dpr}) do
    density = if dpr == 1, do: "", else: " @#{format_dpr(dpr)}x"
    "#{width} × #{height}#{density}"
  end

  defp format_dpr(dpr) when is_integer(dpr), do: Integer.to_string(dpr)
  defp format_dpr(dpr) when dpr == trunc(dpr), do: dpr |> trunc() |> Integer.to_string()
  defp format_dpr(dpr), do: :erlang.float_to_binary(dpr / 1, decimals: 1)

  @browsers [
    {"Edg/", "Edge"},
    {"Firefox/", "Firefox"},
    {"Chrome/", "Chrome"},
    {"Safari/", "Safari"}
  ]
  @systems [
    {"iPhone", "iOS"},
    {"iPad", "iPadOS"},
    {"Android", "Android"},
    {"Mac OS X", "macOS"},
    {"Windows", "Windows"},
    {"Linux", "Linux"}
  ]

  @doc """
  Names the browser and system in a user agent, such as `"Safari on iOS"`,
  or returns `nil` when neither is recognized.
  """
  @spec device(String.t() | nil) :: String.t() | nil
  def device(nil), do: nil

  def device(user_agent) do
    case Enum.reject([known(user_agent, @browsers), known(user_agent, @systems)], &is_nil/1) do
      [] -> nil
      parts -> Enum.join(parts, " on ")
    end
  end

  defp known(user_agent, names) do
    Enum.find_value(names, fn {marker, name} ->
      if String.contains?(user_agent, marker), do: name
    end)
  end

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

  @doc "The path and query of a URL, for showing where a user came from."
  @spec path_of(String.t()) :: String.t()
  def path_of(url) do
    case URI.parse(url) do
      %URI{path: path, query: nil} when is_binary(path) -> path
      %URI{path: path, query: query} when is_binary(path) -> path <> "?" <> query
      _other -> url
    end
  end
end
