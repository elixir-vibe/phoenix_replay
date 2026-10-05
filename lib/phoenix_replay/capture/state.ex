defmodule PhoenixReplay.Capture.State do
  @moduledoc """
  Records state that lives only in the browser, which replaying the view's
  `render/1` cannot rebuild.

  The client module's `replayRecorder/1` records what is typed and chosen
  in form controls on its own, under
  `PhoenixReplay.Recording.State.inputs_key/0`. App code reports other
  state with `replayState(key, changes)`, and code that cannot import
  PhoenixReplay, such as another library, with a window event:

      window.dispatchEvent(
        new CustomEvent("phx_replay:state", {
          detail: {key: "search", changes: {query: "shoes"}}
        })
      )

  `key` names the state, and `changes` holds its fields to merge into what
  was recorded under `key` before: a shallow delta. The client keeps the
  latest state of each key, so a recording starts with the state as it
  is; while the page's LiveView is recorded it timestamps each entry and
  sends them in batches as a `"phx_replay:state"` event, which
  `PhoenixReplay.Recorder` hands here and halts, so the view never sees
  it. A batch is:

    * `"span"` — milliseconds from the batch's first entry to sending it
    * `"e"` — entries, `[dt, key, changes]`, `dt` counting milliseconds
      from the batch's first entry

  Batches come from the browser: `key` must be a string of up to
  `:max_key` bytes and `changes` a JSON object of at most
  `:max_entry_bytes`, nested no deeper than 32 levels, or the entry is
  dropped; a batch keeps at most `:max_entries` entries and `:max_bytes`.
  Keys stay strings, and `changes` go through the session's
  `PhoenixReplay.Sanitizer` with `sanitize_params/1`, and through its
  `PhoenixReplay.Redactor` when it is saved.

  Each batch is recorded as a `:state` event, outside `:max_events`, up to
  `:limit` per session. A changed form control, or a change to a key
  reported before, makes a session interactive for `:keep`; the first
  report of any other key, the state the page started with, does not. See
  `PhoenixReplay.Recording.State` for how the player replays them.
  """

  alias PhoenixReplay.Config
  alias PhoenixReplay.Session.Buffer

  @event "phx_replay:state"
  @max_depth 32
  @max_dt 60_000

  @doc "The event name batches arrive as."
  @spec event() :: String.t()
  def event, do: @event

  @doc "The settings the browser records with, for `Phoenix.LiveView.push_event/3`."
  @spec settings(Config.state()) :: map()
  def settings(state),
    do:
      Map.take(state, [
        :flush,
        :max_entries,
        :max_key,
        :max_entry_bytes,
        :max_bytes,
        :inputs,
        :debounce
      ])

  @doc "Records a batch sent by the browser for the session `pid` records."
  @spec capture(pid(), map(), Config.state()) :: :ok | :dropped | :error
  def capture(pid, params, state) do
    with {:ok, session, sanitizer} <- Buffer.attribute([pid]),
         {:ok, data} <- parse(params, state, sanitizer) do
      Buffer.collect(session, :state, data, "state", state.limit)
    else
      _invalid -> :error
    end
  end

  @doc """
  Validates a batch: returns its entries within the `state` limits, their
  changes sanitized with `sanitizer`, or `:error` when none is usable.
  """
  @spec parse(map(), Config.state(), module()) :: {:ok, map()} | :error
  def parse(%{"span" => span, "e" => entries}, state, sanitizer)
      when is_integer(span) and span >= 0 and is_list(entries) do
    entries =
      entries
      |> Enum.take(state.max_entries)
      |> Enum.flat_map(&entry(&1, state))
      |> within(state.max_bytes)
      |> Enum.map(fn [dt, key, changes] -> [dt, key, sanitizer.sanitize_params(changes)] end)

    if entries == [],
      do: :error,
      else: {:ok, %{span: min(span, @max_dt), entries: entries}}
  end

  def parse(_params, _state, _sanitizer), do: :error

  defp entry([dt, key, changes], state)
       when is_integer(dt) and is_binary(key) and key != "" and is_map(changes) do
    if byte_size(key) <= state.max_key and json?(changes, @max_depth) and
         size(changes) <= state.max_entry_bytes,
       do: [[dt |> max(0) |> min(@max_dt), key, changes]],
       else: []
  end

  defp entry(_entry, _state), do: []

  # The entries that fit in `max_bytes`, in order.
  defp within(entries, max_bytes) do
    entries
    |> Enum.reduce_while({[], 0}, fn [_dt, _key, changes] = entry, {kept, bytes} ->
      bytes = bytes + size(changes)
      if bytes <= max_bytes, do: {:cont, {[entry | kept], bytes}}, else: {:halt, {kept, bytes}}
    end)
    |> elem(0)
    |> Enum.reverse()
  end

  # LiveView decodes event params from JSON, so they hold only JSON values;
  # only the nesting is bounded here.
  defp json?(_value, 0), do: false

  defp json?(map, depth) when is_map(map),
    do: Enum.all?(map, fn {_k, v} -> json?(v, depth - 1) end)

  defp json?(list, depth) when is_list(list), do: Enum.all?(list, &json?(&1, depth - 1))
  defp json?(_scalar, _depth), do: true

  defp size(changes), do: changes |> JSON.encode!() |> byte_size()
end
