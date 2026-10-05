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

  @doc "Formats an offset as `m:ss.cc`, to the hundredth of a second."
  @spec precise_clock(non_neg_integer()) :: String.t()
  def precise_clock(ms) do
    hundredths = ms |> rem(1000) |> div(10) |> Integer.to_string() |> String.pad_leading(2, "0")
    "#{clock(ms)}.#{hundredths}"
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

  @doc "Formats a Unix millisecond timestamp as UTC `Oct 4, 08:50`."
  @spec started(integer()) :: String.t()
  def started(unix_ms) do
    unix_ms |> DateTime.from_unix!(:millisecond) |> Calendar.strftime("%b %-d, %H:%M")
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

  @doc """
  A viewport's orientation as CSS's `orientation` media feature tells it:
  portrait when it is at least as tall as it is wide.
  """
  @spec orientation(%{width: pos_integer(), height: pos_integer()}) :: :portrait | :landscape
  def orientation(%{width: width, height: height}) when height >= width, do: :portrait
  def orientation(_viewport), do: :landscape

  defp format_dpr(dpr) when is_integer(dpr), do: Integer.to_string(dpr)
  defp format_dpr(dpr) when dpr == trunc(dpr), do: dpr |> trunc() |> Integer.to_string()
  defp format_dpr(dpr), do: :erlang.float_to_binary(dpr / 1, decimals: 1)

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
