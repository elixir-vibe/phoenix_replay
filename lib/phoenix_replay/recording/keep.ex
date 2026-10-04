defmodule PhoenixReplay.Recording.Keep do
  @moduledoc """
  Decides whether a session is saved, from the `:keep` configuration.

  A session matching `errors: true` or `slower_than: ms` is always saved.
  Otherwise a session without user interaction is discarded, and the
  `:rate` share of the rest is saved. See "Tail sampling" in
  `PhoenixReplay.Config`.

  The decision only ever turns from discard to keep as events arrive: once
  a session is kept, later events cannot discard it. That lets
  `PhoenixReplay.Session.Monitor` start writing a running session to
  storage as soon as it is kept, observing its events incrementally with
  `observe/3` and `decision/3`.
  """

  alias PhoenixReplay.{Config, Recording}
  alias PhoenixReplay.Recording.Event

  @type reason :: :not_interactive | :not_sampled

  @typedoc "What `observe/3` has seen of a session's events so far."
  @type observation :: %{event?: boolean(), params: non_neg_integer(), flagged?: boolean()}

  @doc "An observation of no events."
  @spec new() :: observation()
  def new, do: %{event?: false, params: 0, flagged?: false}

  @doc "Adds `events` to an observation."
  @spec observe(observation(), [Event.t()], Config.keep()) :: observation()
  def observe(observation, events, keep) do
    Enum.reduce(events, observation, fn event, acc ->
      %{
        event?: acc.event? or event.type == :event,
        params: acc.params + if(event.type == :params, do: 1, else: 0),
        flagged?: acc.flagged? or flagged?(event, keep)
      }
    end)
  end

  @doc """
  Decides from an observation, given a uniform `draw` in `0.0..1.0` for
  `:rate`.

  A session is interactive once it handled an event or navigated within
  the LiveView, that is, after more than its initial `handle_params/3`.
  """
  @spec decision(observation(), Config.keep(), float()) :: :keep | {:discard, reason()}
  def decision(observation, keep, draw) do
    cond do
      observation.flagged? -> :keep
      not (observation.event? or observation.params >= 2) -> {:discard, :not_interactive}
      draw <= keep.rate and keep.rate > 0 -> :keep
      true -> {:discard, :not_sampled}
    end
  end

  @doc "Decides for a whole recording. See `decision/3`."
  @spec decide(Recording.t(), Config.keep(), float()) :: :keep | {:discard, reason()}
  def decide(%Recording{} = recording, keep, draw \\ :rand.uniform()) do
    new() |> observe(recording.events, keep) |> decision(keep, draw)
  end

  defp flagged?(event, %{errors: errors, slower_than: slower_than}) do
    (errors and Event.error?(event)) or slow?(event, slower_than)
  end

  defp slow?(_event, nil), do: false

  defp slow?(event, slower_than) do
    case Event.duration(event) do
      nil -> false
      duration -> duration >= slower_than
    end
  end
end
