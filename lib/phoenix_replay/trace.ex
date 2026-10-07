defmodule PhoenixReplay.Trace do
  @moduledoc """
  Reads recordings from code: from IEx, a script, a test, or a coding agent
  running code in your app. Everything is plain data, to inspect as it is.

      iex> [summary | _] = PhoenixReplay.Trace.find(errors: true, within: "24h")
      iex> PhoenixReplay.Trace.events(summary.id)
      [%{index: 0, at: 0, type: :mount, label: "mount", ...}, ...]
      iex> PhoenixReplay.Trace.state(summary.id, 14)
      %{index: 14, assigns: %{...}, changed: [%{path: "tasks[id: 7].done", ...}], ...}

  Indexes are the player's, so `/replay/<id>?at=<index>` in the dashboard
  opens the same moment. A session still running is read from the buffer
  of the VM that records it, redacted as the dashboard redacts it; call
  these functions in that VM to see it. `mix phoenix_replay.list` and
  `mix phoenix_replay.show` print them from the command line, for saved
  recordings.
  """

  alias PhoenixReplay.{Catalog, Config, Recording}
  alias PhoenixReplay.Recording.{Client, Diff, Event, Filter, State, Summary, Timeline}

  @filters [
    :text,
    :view,
    :event,
    :mark,
    :source,
    :medium,
    :campaign,
    :device_type,
    :browser,
    :release,
    :within,
    :from,
    :to,
    :longer_than,
    :min_events,
    :errors,
    :tab,
    :live,
    :limit
  ]

  @typedoc """
  One event of a recording:

    * `:index` and `:at` — its place in the player and its offset in
      milliseconds from the session's start
    * `:type` — see `PhoenixReplay.Recording.Event`
    * `:label` — one line as the player's event list shows it
    * `:error?` — whether it reports an error: an error log, a failed
      query, or the view's crash
    * `:caused_by` — the index of the interaction it belongs to, the user
      event, navigation, message or mount that caused it, or `nil` for
      that interaction itself
    * `:data` — what was recorded, as `PhoenixReplay.Recording.Event`
      describes it
  """
  @type event :: %{
          index: non_neg_integer(),
          at: non_neg_integer(),
          type: Event.type(),
          label: String.t(),
          error?: boolean(),
          caused_by: non_neg_integer() | nil,
          data: map()
        }

  @typedoc "A change the event made inside an assign, at a path such as `tasks[id: 7].done`."
  @type change :: %{
          path: String.t(),
          change: :changed | :added | :removed,
          before: term(),
          after: term()
        }

  @typedoc """
  The view at one moment: the event there, the URL, the viewport, the
  view's assigns, the LiveComponents' assigns by `{module, id}`, the state
  the browser reported (see `PhoenixReplay.Recording.State`), and what the
  event changed.
  """
  @type state :: %{
          index: non_neg_integer(),
          at: non_neg_integer(),
          event: event(),
          url: String.t() | nil,
          viewport: Recording.viewport() | nil,
          assigns: map(),
          components: map(),
          client_state: map(),
          changed: [change()]
        }

  @doc """
  Summaries of the recordings matching `filters`, running sessions first,
  then saved ones, most recent first.

    * `:text` — found in the URL, id, event or mark names, source or
      campaign
    * `:view` — the view module, such as `MyAppWeb.CheckoutLive`
    * `:event` — a `handle_event/3` name the session triggered
    * `:mark` — the name of a moment the session reached, such as
      `"my_app.checkout.completed"`
    * `:source`, `:medium` and `:campaign` — where the visit came from,
      such as `"google"`, `"cpc"` and `"spring"`, or `"(direct)"`; see
      `PhoenixReplay.Recording.Client.traffic/1`
    * `:device_type` — `"phone"`, `"tablet"` or `"desktop"`
    * `:browser` — the browser's family, such as `"Mobile Safari"`
    * `:release` — the release the session was recorded with
    * `:within` — `"15m"`, `"1h"`, `"24h"`, `"7d"` or `"30d"` since the
      session started
    * `:from` and `:to` — a `DateTime` the session started at or after,
      and at or before
    * `:longer_than` — lasting at least that many seconds
    * `:min_events` — at least that many events
    * `:errors` — `true` for sessions with an error only
    * `:tab` — the sessions of one browser tab
    * `:live` — `true` for running sessions only, `false` for saved ones
    * `:limit` — how many to return (default `20`)
  """
  @spec find(keyword(), Config.t()) :: [Summary.t()]
  def find(filters \\ [], config \\ Config.load()) do
    filters = Keyword.validate!(filters, @filters)
    limit = Keyword.get(filters, :limit, 20)
    filter = filter(filters)
    now = System.system_time(:millisecond)

    running = if filters[:live] == false, do: [], else: Catalog.live(filter, now)

    saved =
      if filters[:live] == true,
        do: [],
        else: config |> Catalog.query(filter, now: now, limit: limit) |> elem(0)

    Enum.take(running ++ saved, limit)
  end

  @doc "The recording with `id`, from the buffer while it runs or from storage."
  @spec fetch(Recording.id(), Config.t()) :: {:ok, Recording.t()} | {:error, :not_found}
  def fetch(id, config \\ Config.load()) do
    case Catalog.fetch(config, id) do
      {:ok, recording} -> {:ok, recording}
      {:error, _reason} -> {:error, :not_found}
    end
  end

  @doc """
  The events of a recording, or of the recording with that id, as the
  player lists them. Pointer batches are left out; client state is an
  event per report.
  """
  @spec events(Recording.t() | Recording.id()) :: [event()]
  def events(recording), do: recording |> playback() |> listed()

  # The events of a recording laid out for playback.
  defp listed(%Recording{events: events}) do
    events
    |> Timeline.interactions()
    |> Enum.flat_map(fn {{_head, head_index} = head, rows} ->
      [event(head, nil) | Enum.map(rows, &event(&1, head_index))]
    end)
  end

  @doc """
  The view at the event at `index`, as the player shows it there: its
  assigns, its components, the client state, and what the event changed.
  """
  @spec state(Recording.t() | Recording.id(), non_neg_integer()) :: state()
  def state(recording, index) do
    playback = playback(recording)

    if playback.events == [],
      do: raise(ArgumentError, "recording #{playback.id} has no events to show a moment of")

    timeline = Timeline.at(playback, index)
    {client_state, assigns} = Map.pop(timeline.assigns, State.assign(), %{})

    %{
      index: timeline.index,
      at: timeline.event.at,
      event: playback |> listed() |> Enum.at(timeline.index),
      url: timeline.url,
      viewport: timeline.viewport,
      assigns: assigns,
      components: timeline.components,
      client_state: client_state,
      changed: changes(timeline)
    }
  end

  defp playback(id) when is_binary(id) do
    case fetch(id) do
      {:ok, recording} -> playback(recording)
      {:error, :not_found} -> raise ArgumentError, "no recording #{inspect(id)}"
    end
  end

  defp playback(%Recording{} = recording), do: recording |> Timeline.for_playback() |> elem(0)

  defp event({%Event{} = event, index}, caused_by) do
    %{
      index: index,
      at: event.at,
      type: event.type,
      label: Event.label(event),
      error?: Event.error?(event),
      caused_by: caused_by,
      data: event.data
    }
  end

  defp changes(timeline) do
    Enum.flat_map(Event.changed_keys(timeline.event), fn key ->
      timeline.before
      |> Map.get(key)
      |> Diff.changes(Map.get(timeline.assigns, key))
      |> Enum.map(&change(key, &1))
    end)
  end

  defp change(key, change) do
    {kind, steps, before, after_value} =
      case change do
        {:changed, steps, before, after_value} -> {:changed, steps, before, after_value}
        {:added, steps, value} -> {:added, steps, nil, value}
        {:removed, steps, value} -> {:removed, steps, value, nil}
      end

    %{path: Diff.path(key, steps), change: kind, before: before, after: after_value}
  end

  defp filter(filters) do
    %Filter{
      query: filters[:text],
      view: view_name(filters[:view]),
      event: filters[:event],
      mark: filters[:mark],
      source: filters[:source],
      medium: filters[:medium],
      campaign: filters[:campaign],
      device_type: device_type(filters[:device_type]),
      browser: filters[:browser],
      release: filters[:release],
      within: within(filters[:within]),
      from: time(:from, filters[:from]),
      to: time(:to, filters[:to]),
      longer_than: positive(:longer_than, filters[:longer_than]),
      min_events: positive(:min_events, filters[:min_events]),
      errors: filters[:errors] == true,
      tab: filters[:tab]
    }
  end

  # A window the dashboard offers, so the filter can count back from now.
  defp within(nil), do: nil

  defp within(window) do
    if window in Filter.windows(),
      do: window,
      else:
        raise(
          ArgumentError,
          ":within must be one of #{Enum.join(Filter.windows(), ", ")}, got: #{inspect(window)}"
        )
  end

  defp positive(_name, nil), do: nil
  defp positive(_name, count) when is_integer(count) and count > 0, do: count

  defp positive(name, count),
    do:
      raise(ArgumentError, "#{inspect(name)} must be a positive integer, got: #{inspect(count)}")

  defp time(_name, nil), do: nil
  defp time(_name, %DateTime{} = time), do: DateTime.to_unix(time, :millisecond)

  defp time(name, time),
    do: raise(ArgumentError, "#{inspect(name)} must be a DateTime, got: #{inspect(time)}")

  defp device_type(nil), do: nil

  defp device_type(type) do
    if type in Client.device_types(),
      do: type,
      else:
        raise(
          ArgumentError,
          ":device_type must be one of #{Enum.join(Client.device_types(), ", ")}, got: #{inspect(type)}"
        )
  end

  # A view module, or its name as the dashboard shows it.
  defp view_name(view) when is_atom(view) and not is_nil(view), do: inspect(view)
  defp view_name(view), do: view
end
