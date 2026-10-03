defmodule PhoenixReplay.Recording.Keep do
  @moduledoc """
  Decides whether a finished session is saved, from the `:keep` configuration.

  A session matching `errors: true` or `slower_than: ms` is always saved.
  Otherwise a session without user interaction is discarded, and the
  `:rate` share of the rest is saved. See "Tail sampling" in
  `PhoenixReplay.Config`.
  """

  alias PhoenixReplay.{Config, Recording}
  alias PhoenixReplay.Recording.{Event, Timeline}

  @type reason :: :not_interactive | :not_sampled

  @doc """
  Decides for `recording`, given a uniform `draw` in `0.0..1.0` for `:rate`.
  """
  @spec decide(Recording.t(), Config.keep(), float()) :: :keep | {:discard, reason()}
  def decide(%Recording{} = recording, keep, draw \\ :rand.uniform()) do
    cond do
      flagged?(recording.events, keep) -> :keep
      not Timeline.interactive?(recording) -> {:discard, :not_interactive}
      draw <= keep.rate and keep.rate > 0 -> :keep
      true -> {:discard, :not_sampled}
    end
  end

  defp flagged?(events, %{errors: errors, slower_than: slower_than}) do
    Enum.any?(events, fn event ->
      (errors and Event.error?(event)) or slow?(event, slower_than)
    end)
  end

  defp slow?(_event, nil), do: false

  defp slow?(event, slower_than) do
    case Event.duration(event) do
      nil -> false
      duration -> duration >= slower_than
    end
  end
end
