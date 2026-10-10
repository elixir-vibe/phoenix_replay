defmodule PhoenixReplay.Session.Visits do
  @moduledoc """
  Samples and keeps recordings by visit, the unit a person's time on the
  site is counted in; see `PhoenixReplay.Plug`.

  ## Sampling

  `draws/1` gives a visit's draws for `:sample_rate` and for
  `keep: [rate: ...]`, made from its id, which is random and made when the
  visit lands. Every recording of the visit draws the same, so a visit is
  recorded or not as a whole. The two draws are independent, so the two
  rates multiply as they do for a recording alone. A recording without a
  visit draws at random.

  ## Keeping

  A visit is kept when any of its recordings would be kept on its own,
  and then all of its recordings are saved, pages without interaction
  included. `PhoenixReplay.Session.Monitor` keeps this state: when a
  recording ends and neither it nor an earlier recording of its visit was
  kept, its decision is held, with its events in the buffer, until another
  recording of the visit is kept, which saves it too, or the visit ends,
  which discards it.

  A visit ends when none of its recordings runs and none has started for
  the visit's timeout (`Config.visit_timeout/1`) since the last one ended,
  as a visit ends after that long without a request. Held recordings count
  towards `:max_memory`; while the buffer is larger, the recordings held
  for the visit idle longest are discarded.

  The state lives in the monitor's process, on one node: a monitor that
  restarts holds the recordings still buffered again, and a visit whose
  requests reach several nodes is kept on each by its recordings there.
  """

  alias PhoenixReplay.Recording

  # Draws are hashed into this many steps of the unit interval.
  @steps 4_294_967_296

  @typedoc "A visit's keeping state."
  @type visit :: %{
          kept?: boolean(),
          running: MapSet.t(Recording.id()),
          # Newest first.
          held: [{Recording.id(), atom()}],
          ended_at: integer() | nil,
          timeout: pos_integer()
        }

  @type t :: %{String.t() => visit()}

  @doc "No visits."
  @spec new() :: t()
  def new, do: %{}

  @doc """
  A visit's draws for `:sample_rate` and for `keep: [rate: ...]`, each in
  `0.0..1.0`: from the visit's id, or at random without one.
  """
  @spec draws(String.t() | nil) :: {float(), float()}
  def draws(nil), do: {:rand.uniform(), :rand.uniform()}
  def draws(visit), do: {draw(visit, :sample), draw(visit, :keep)}

  defp draw(visit, salt), do: (:erlang.phash2({visit, salt}, @steps) + 1) / @steps

  @doc "Notes that recording `id` of `visit` runs, which keeps the visit open."
  @spec started(t(), String.t(), Recording.id(), pos_integer()) :: t()
  def started(visits, visit, id, timeout) do
    entry =
      Map.get(visits, visit, %{
        kept?: false,
        running: MapSet.new(),
        held: [],
        ended_at: nil,
        timeout: timeout
      })

    Map.put(visits, visit, %{
      entry
      | running: MapSet.put(entry.running, id),
        ended_at: nil,
        timeout: timeout
    })
  end

  @doc "Whether a recording of `visit` was kept."
  @spec kept?(t(), String.t() | nil) :: boolean()
  def kept?(_visits, nil), do: false
  def kept?(visits, visit), do: match?(%{^visit => %{kept?: true}}, visits)

  @doc """
  Keeps `visit`, returning the recordings held for it, which are now to
  be saved.
  """
  @spec keep(t(), String.t()) :: {t(), [Recording.id()]}
  def keep(visits, visit) do
    case visits do
      %{^visit => entry} ->
        {%{visits | visit => %{entry | kept?: true, held: []}},
         entry.held |> Enum.reverse() |> Enum.map(&elem(&1, 0))}

      %{} ->
        {visits, []}
    end
  end

  @doc "Notes that recording `id` ended at `now`, kept or not."
  @spec ended(t(), String.t(), Recording.id(), integer()) :: t()
  def ended(visits, visit, id, now) do
    case visits do
      %{^visit => entry} ->
        running = MapSet.delete(entry.running, id)
        ended_at = if MapSet.size(running) == 0, do: now, else: entry.ended_at
        %{visits | visit => %{entry | running: running, ended_at: ended_at}}

      %{} ->
        visits
    end
  end

  @doc """
  Holds the decision of recording `id`, which ended at `now` and would be
  discarded for `reason`, until its visit is kept or ends.
  """
  @spec hold(t(), String.t(), Recording.id(), atom(), integer()) :: t()
  def hold(visits, visit, id, reason, now) do
    visits = ended(visits, visit, id, now)

    case visits do
      %{^visit => entry} -> %{visits | visit => %{entry | held: [{id, reason} | entry.held]}}
      %{} -> visits
    end
  end

  @doc """
  Ends the visits that have been idle for their timeout at `now`: drops
  them, and returns the recordings held for them, now to be discarded,
  with their reasons.
  """
  @spec expire(t(), integer()) :: {t(), [{Recording.id(), atom()}]}
  def expire(visits, now) do
    {ended, open} =
      Enum.split_with(visits, fn {_visit, entry} ->
        entry.ended_at != nil and now - entry.ended_at >= entry.timeout
      end)

    {Map.new(open), Enum.flat_map(ended, fn {_visit, entry} -> Enum.reverse(entry.held) end)}
  end

  @doc """
  Lets go of the recordings held for the visit idle longest, for
  discarding them early, returning them with their reasons, or `[]` when
  nothing is held.
  """
  @spec release_oldest(t()) :: {t(), [{Recording.id(), atom()}]}
  def release_oldest(visits) do
    visits
    |> Enum.filter(fn {_visit, entry} -> entry.held != [] end)
    |> Enum.min_by(fn {_visit, entry} -> entry.ended_at || 0 end, fn -> nil end)
    |> case do
      nil -> {visits, []}
      {visit, entry} -> {%{visits | visit => %{entry | held: []}}, Enum.reverse(entry.held)}
    end
  end

  @doc "Whether any visit is open or holds recordings, so expiry should be checked."
  @spec any?(t()) :: boolean()
  def any?(visits), do: visits != %{}
end
