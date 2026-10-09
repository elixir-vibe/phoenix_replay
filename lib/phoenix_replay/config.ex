defmodule PhoenixReplay.Config do
  @moduledoc """
  Validated runtime configuration.

  This is the only module that reads the `:phoenix_replay` application
  environment. Everything else receives a `t:t/0` explicitly, which keeps
  configuration decisions at the boundary and lets tests pass their own.

  ## Options

    * `:storage` — `{module, opts}` implementing `PhoenixReplay.Storage`.
      Defaults to `{PhoenixReplay.Storage.File, []}`.
    * `:sanitizer` — module implementing `PhoenixReplay.Sanitizer`.
      Defaults to `PhoenixReplay.Sanitizer.Default`.
    * `:max_events` — events recorded per session before recording stops.
      Defaults to `10_000`.
    * `:sample_rate` — share of sessions to record, from `0.0` to `1.0`.
      Defaults to `1.0`, recording every session. `0.0` turns recording off.
    * `:keep` — keyword list choosing which recorded sessions are saved
      when they end, as described in "Tail sampling" below:
      * `:rate` — share of interactive sessions to save (default `1.0`)
      * `:errors` — always save sessions with an error (default `false`)
      * `:marks` — always save sessions with a telemetry event collected
        with `mark: true`, such as a completed checkout (default `false`)
      * `:slower_than` — always save sessions with a collected event
        lasting at least this many milliseconds (default `nil`)
    * `:collect` — telemetry events to record alongside LiveView events.
      Each entry is a `PhoenixReplay.Collector` module, `{module, opts}`,
      an event name, or `{event_name, opts}` for
      `PhoenixReplay.Collector.Generic`. Every entry accepts `:limit`,
      the events recorded per session (default `1_000`). Defaults to `[]`.
    * `:logs` — keyword list enabling `Logger` collection, or `nil` (the
      default) to leave logs out. See `PhoenixReplay.Capture.Logs`.
    * `:redact` — a `PhoenixReplay.Redactor` that masks sensitive values
      when a recording is saved: a list of regexes, or regex sources as
      strings, for `PhoenixReplay.Redactor.Patterns`, or `{module, opts}`.
      Defaults to `[]`, which stores recordings as the sanitizer left them.
    * `:flush` — keyword list controlling how running sessions are written
      to storage in chunks, when the storage supports it (see
      `PhoenixReplay.Storage`), or `false` to save each session only when
      it ends:
      * `:events` — events buffered before a chunk is written (default `200`)
      * `:interval` — milliseconds after which buffered events are written
        anyway (default `5_000`)
    * `:pointer` — records the pointer, touches and scrolling, for the
      player to show over the replay, when the client module's
      `replayRecorder/1` runs in the browser. `true` uses the defaults; a
      keyword list sets any of them; `false` (the default) records none:
      * `:sample` — milliseconds between recorded pointer positions
        (default `50`)
      * `:scroll` — milliseconds between recorded scroll positions
        (default `100`)
      * `:flush` — milliseconds between the batches the browser sends
        (default `1_000`)
      * `:max_points` — positions, presses and scrolls a batch may hold; a
        fuller batch is sent early, and the server drops the rest
        (default `500`)
      * `:limit` — batches recorded per session (default `3_600`, an hour
        of movement at the default `:flush`)
    * `:state` — records state that lives only in the browser, when the
      client module's `replayRecorder/1` runs: what is typed and chosen in
      form controls, and what app code reports with `replayState/2`; see
      `PhoenixReplay.Capture.State`. On by default; `false` records none,
      and a keyword list sets any of:
      * `:inputs` — whether form controls are recorded (default `true`).
        Passwords, hidden inputs, card fields and one-time codes are never read; see
        "Client state" in the recording guide
      * `:debounce` — milliseconds a form control must stay unchanged
        before its value is recorded, so typing a sentence is one entry
        (default `300`)
      * `:flush` — milliseconds between the batches the browser sends
        (default `1_000`)
      * `:max_entries` — entries a batch may hold; a fuller batch is sent
        early, and the server drops the rest (default `200`)
      * `:max_key` — bytes a key may have (default `64`)
      * `:max_entry_bytes` — the JSON size an entry's changes may have;
        larger ones are dropped (default `8_192`)
      * `:max_bytes` — the JSON size a batch may have; a fuller batch is
        sent early, and the server drops the rest (default `65_536`)
      * `:limit` — batches recorded per session (default `3_600`)
    * `:client` — what recordings keep in `client` about the browser and
      the visit. `:context` is its former name, still read, with a
      warning:
      * `:media` — the media settings the browser reports with its
        viewport, which the replay applies to the page: a list of
        `:color_scheme`, `:reduced_motion`, `:contrast`, `:pointer` and
        `:hover` (default all of them), or `false` for none. See "What the
        browser sends" in the privacy guide
      * `:headers` — request header names to capture, refreshed on each
        request (default `[]`). `cookie`, `authorization` and
        `proxy-authorization` are refused.
      * `:landing` — keyword list capturing the visit's landing request, or
        `nil` (the default):
        * `:params` — query params to keep: names, or the presets `:utm`
          (`utm_source`, `utm_medium`, `utm_campaign`, `utm_term`,
          `utm_content`) and `:click_ids` (`gclid`, `fbclid`, `msclkid`)
        * `:referrer` — `true` keeps the `Referer` without its query
          string, `:full` keeps all of it, `false` none (default `true`)
        * `:attribution` — `:first` keeps the first landing of the visit;
          `:last` replaces it whenever a request carries tracked params
          (default `:first`). Either way, a request whose tracked params
          differ from the landing's starts a new visit.
        * `:timeout` — milliseconds without a request after which the next
          request starts a new visit (default 30 minutes, also without
          `:landing`); see `PhoenixReplay.Plug`
    * `:release` — the name of the running deploy, such as a commit from
      your host's environment, recorded with each session, shown in the
      player and filterable in the list; `nil` (the default) uses the
      version of the view's application. Only for people: nothing is
      decided by it; see `PhoenixReplay.Recording.Code`.
    * `:replay` — a `PhoenixReplay.Replay` module adapting how recordings
      replay, such as the assigns older recordings hold, or `nil` (the
      default).
    * `:max_memory` — bytes of buffered recordings above which new
      sessions are not recorded, or `nil` (the default) for no limit.
    * `:retention` — keyword list controlling `PhoenixReplay.Storage.Retention`:
      * `:max_age` — milliseconds after which recordings are deleted
      * `:max_count` — number of most recent recordings to keep
      * `:interval` — milliseconds between pruning runs (default `60_000`)
    * `:export` — video export with `PhoenixReplay.Export`, off by default.
      A keyword list turns it on; `:endpoint` is required:
      * `:endpoint` — your endpoint, which serves the stylesheets and
        scripts the replayed pages load
      * `:frame_layout` — `{module, function}` root layout for exported
        replays, as the router's option of that name (default the
        dashboard's frame layout)
      * `:dir` — where finished videos are kept (default
        `phoenix_replay/exports` in the system's temporary directory)
      * `:ttl` — milliseconds a finished video is kept (default `3_600_000`)
      * `:max_concurrency` — videos exported at once; more wait their turn
        (default `1`). `PhoenixReplay.Export.Queue.Oban` takes its limit
        from its Oban queue instead.
      * `:queue` — where exports wait and run, a
        `PhoenixReplay.Export.Queue`: a module or `{module, opts}`
        (default `PhoenixReplay.Export.Queue.Local`)
      * `:fps` — frames per second (default `30`)
      * `:max_dpr` — the highest device pixel ratio to render at, which
        bounds the video's size (default `2`)
      * `:idle` — milliseconds a stretch without activity is shortened to,
        or `nil` to keep it whole (default `3_000`)
      * `:hold` — milliseconds the last moment is held at the end
        (default `1_000`)
      * `:crf` — the H.264 quality, lower is better (default `23`)
      * `:preset` — the x264 speed preset (default `"veryfast"`)
      * `:ffmpeg` — the `ffmpeg` executable (default `"ffmpeg"`)
      * `:playwright` — options for `PlaywrightEx.Supervisor`, such as
        `:executable` or `:ws_endpoint` (default `[]`)
      * `:max_shots` — the most screenshots an export may take, as files
        until the video is encoded; longer exports fail with a message to
        choose a shorter range (default `3_600`, two minutes of pointer
        movement at 30 fps)
      * `:timeout` — milliseconds a browser step may take, and ffmpeg may
        go without reporting progress (default `30_000`)
    * `:persist` — keyword list controlling `PhoenixReplay.Session.Finalizer`:
      * `:attempts` — save attempts before giving up (default `3`)
      * `:backoff` — base delay in milliseconds, multiplied by the attempt
        number (default `1_000`)

  ## Switching options off and overriding them

  `:flush`, `:logs`, `:pointer`, `:state`, `:export`, `:redact`,
  `:max_memory` and the client's `:landing` and `:media` can be switched off with `nil`
  or `false`.

  For `:flush`, `:logs`, `:pointer`, `:state`, `:export` and `:landing`, `true` turns
  one on with whatever is already set, or its defaults, and a keyword list
  sets some of its settings onto that, as `:keep`, `:retention` and
  `:persist` do. So a live session's `{PhoenixReplay.Recorder, flush:
  [events: 50]}` keeps the application's `:interval`. `:redact` and
  `:max_memory` have no defaults to turn on: give them a value.

  ## Tail sampling

  `:sample_rate` decides when a session mounts whether it is recorded.
  `:keep` decides when it ends whether it is saved: a session with an
  error, a mark or a slow event matching `:errors`, `:marks` or
  `:slower_than` is always saved, a session without user interaction is discarded, and `:rate` of
  the rest are saved.

  To save every failing session but only a few others, record every session
  and keep a share of them:

      config :phoenix_replay,
        sample_rate: 1.0,
        keep: [rate: 0.05, errors: true, slower_than: 1_000],
        max_memory: 256 * 1024 * 1024

  Every session is then buffered until it ends, so set `:max_memory`.
  """

  # Defaults of the options that can be switched off. `nil` and `false`
  # switch one off, `true` turns it on with these, and a keyword list sets
  # some of them, onto whatever is already set.
  @flush %{events: 200, interval: 5_000}
  @logs %{level: :info, metadata: [], limit: 1_000}
  @pointer %{sample: 50, scroll: 100, flush: 1_000, max_points: 500, limit: 3_600}
  @state %{
    flush: 1_000,
    max_entries: 200,
    max_key: 64,
    max_entry_bytes: 8_192,
    max_bytes: 65_536,
    limit: 3_600,
    inputs: true,
    debounce: 300
  }
  # A visit ends after half an hour without a request, as web analytics count one.
  @visit_timeout 1_800_000
  @landing %{params: [], referrer: true, attribution: :first, timeout: @visit_timeout}
  @media [:color_scheme, :reduced_motion, :contrast, :pointer, :hover]
  @export %{
    endpoint: nil,
    frame_layout: nil,
    dir: nil,
    ttl: 3_600_000,
    max_concurrency: 1,
    queue: nil,
    fps: 30,
    max_dpr: 2,
    idle: 3_000,
    hold: 1_000,
    crf: 23,
    preset: "veryfast",
    ffmpeg: "ffmpeg",
    playwright: [],
    max_shots: 3_600,
    timeout: 30_000
  }
  @off [nil, false]

  @secret_headers ~w(cookie authorization proxy-authorization)
  @param_presets %{
    utm: ~w(utm_source utm_medium utm_campaign utm_term utm_content),
    click_ids: ~w(gclid fbclid msclkid)
  }

  @type retention :: %{
          max_age: pos_integer() | nil,
          max_count: non_neg_integer() | nil,
          interval: pos_integer()
        }

  @type persist :: %{attempts: pos_integer(), backoff: non_neg_integer()}

  @type keep :: %{
          rate: float(),
          errors: boolean(),
          marks: boolean(),
          slower_than: pos_integer() | nil
        }

  @typedoc "A `PhoenixReplay.Collector` and its options."
  @type collector :: {module(), keyword()}

  @typedoc "A `PhoenixReplay.Redactor` module and its options."
  @type redactor :: {module(), keyword()}

  @type flush :: %{events: pos_integer(), interval: pos_integer()}

  @type pointer :: %{
          sample: pos_integer(),
          scroll: pos_integer(),
          flush: pos_integer(),
          max_points: pos_integer(),
          limit: pos_integer()
        }

  @type state :: %{
          flush: pos_integer(),
          max_entries: pos_integer(),
          max_key: pos_integer(),
          max_entry_bytes: pos_integer(),
          max_bytes: pos_integer(),
          limit: pos_integer(),
          inputs: boolean(),
          debounce: pos_integer()
        }

  @type landing :: %{
          params: [String.t()],
          referrer: boolean() | :full,
          attribution: :first | :last,
          timeout: pos_integer()
        }

  @typedoc "A media setting a viewport may carry; see `t:PhoenixReplay.Recording.viewport/0`."
  @type media :: :color_scheme | :reduced_motion | :contrast | :pointer | :hover

  @type client :: %{headers: [String.t()], landing: landing() | nil, media: [media()]}

  @type export :: %{
          endpoint: module() | nil,
          frame_layout: {module(), atom()} | nil,
          dir: Path.t() | nil,
          ttl: pos_integer(),
          max_concurrency: pos_integer(),
          queue: module() | {module(), keyword()} | nil,
          fps: pos_integer(),
          max_dpr: pos_integer(),
          idle: pos_integer() | nil,
          hold: non_neg_integer(),
          crf: non_neg_integer(),
          preset: String.t(),
          ffmpeg: String.t(),
          playwright: keyword(),
          max_shots: pos_integer(),
          timeout: pos_integer()
        }

  @type logs :: %{level: Logger.level(), metadata: [atom()], limit: pos_integer()}

  @typedoc "A storage backend module and its options."
  @type storage :: {module(), keyword()}

  @type t :: %__MODULE__{
          storage: storage(),
          sanitizer: module(),
          max_events: pos_integer(),
          sample_rate: float(),
          keep: keep(),
          collect: [collector()],
          logs: logs() | nil,
          redact: redactor() | nil,
          max_memory: pos_integer() | nil,
          flush: flush() | nil,
          pointer: pointer() | nil,
          state: state() | nil,
          client: client(),
          replay: module() | nil,
          release: String.t() | nil,
          export: export() | nil,
          retention: retention(),
          persist: persist()
        }

  defstruct storage: {PhoenixReplay.Storage.File, []},
            sanitizer: PhoenixReplay.Sanitizer.Default,
            max_events: 10_000,
            sample_rate: 1.0,
            keep: %{rate: 1.0, errors: false, marks: false, slower_than: nil},
            collect: [],
            logs: nil,
            redact: nil,
            max_memory: nil,
            flush: %{events: 200, interval: 5_000},
            pointer: nil,
            state: @state,
            client: %{headers: [], landing: nil, media: @media},
            replay: nil,
            release: nil,
            export: nil,
            retention: %{max_age: nil, max_count: nil, interval: 60_000},
            persist: %{attempts: 3, backoff: 1_000}

  @doc """
  Loads and validates configuration from the application environment.

  `overrides` take precedence over the environment. Module-keyed entries,
  such as an endpoint configured with `otp_app: :phoenix_replay`, belong to
  those modules and are skipped.

  It runs on every request and mount, so the result is kept for each set
  of `overrides` and built again only when the environment changes.
  """
  @spec load(keyword()) :: t()
  def load(overrides \\ []) when is_list(overrides) do
    env =
      :phoenix_replay
      |> Application.get_all_env()
      |> Enum.reject(fn {key, _value} -> module_key?(key) end)

    key = {__MODULE__, :erlang.phash2(overrides)}

    case :persistent_term.get(key, nil) do
      {^env, ^overrides, config} ->
        config

      _stale ->
        config = new(env ++ overrides)
        :persistent_term.put(key, {env, overrides, config})
        config
    end
  end

  @doc """
  Builds a configuration from a keyword list.

  Raises `ArgumentError` for unknown keys or invalid values.
  """
  @spec new(keyword()) :: t()
  def new(opts) when is_list(opts) do
    Enum.reduce(opts, %__MODULE__{}, &put/2)
  end

  @doc """
  Milliseconds without a request after which a visit ends: the client's
  `landing: [timeout: ...]`, or 30 minutes.
  """
  @spec visit_timeout(t()) :: pos_integer()
  def visit_timeout(%__MODULE__{client: %{landing: %{timeout: timeout}}}), do: timeout
  def visit_timeout(%__MODULE__{}), do: @visit_timeout

  defp module_key?(key), do: match?("Elixir." <> _rest, Atom.to_string(key))

  defp put({:storage, {module, opts}}, config) when is_atom(module) and is_list(opts),
    do: %{config | storage: {module, opts}}

  defp put({:storage, module}, config) when is_atom(module),
    do: %{config | storage: {module, []}}

  defp put({:sanitizer, module}, config) when is_atom(module),
    do: %{config | sanitizer: module}

  defp put({:max_events, max}, config) when is_integer(max) and max > 0,
    do: %{config | max_events: max}

  defp put({:sample_rate, rate}, config) when is_number(rate) and rate >= 0 and rate <= 1,
    do: %{config | sample_rate: rate / 1}

  defp put({:keep, opts}, config) when is_list(opts),
    do: %{
      config
      | keep: merge(config.keep, opts, &valid_keep?/2) |> Map.update!(:rate, &(&1 / 1))
    }

  defp put({:collect, entries}, config) when is_list(entries),
    do: %{config | collect: Enum.map(entries, &collector/1)}

  defp put({:logs, value}, config),
    do: %{config | logs: switch(:logs, value, config.logs, @logs, &valid_logs?/2)}

  defp put({:redact, off}, config) when off in [nil, false, []], do: %{config | redact: nil}

  defp put({:redact, patterns}, config) when is_list(patterns),
    do: %{
      config
      | redact: {PhoenixReplay.Redactor.Patterns, patterns: Enum.map(patterns, &pattern/1)}
    }

  defp put({:redact, {module, opts}}, config) when is_atom(module) and is_list(opts),
    do: %{config | redact: {module, opts}}

  defp put({:redact, module}, config) when is_atom(module) and not is_boolean(module),
    do: %{config | redact: {module, []}}

  defp put({:max_memory, off}, config) when off in @off, do: %{config | max_memory: nil}

  defp put({:max_memory, max}, config) when is_integer(max) and max > 0,
    do: %{config | max_memory: max}

  defp put({:client, opts}, config) when is_list(opts) do
    client =
      Enum.reduce(opts, config.client, fn
        {:headers, names}, acc when is_list(names) -> %{acc | headers: Enum.map(names, &header/1)}
        {:landing, value}, acc -> %{acc | landing: landing(value, acc.landing)}
        {:media, value}, acc -> %{acc | media: media(value)}
        {key, value}, _acc -> invalid!(key, value)
      end)

    %{config | client: client}
  end

  defp put({:context, opts}, config) when is_list(opts) do
    IO.warn("config :phoenix_replay, :context is deprecated, use :client", [])
    put({:client, opts}, config)
  end

  defp put({:release, nil}, config), do: %{config | release: nil}

  defp put({:release, release}, config) when is_binary(release) and release != "",
    do: %{config | release: release}

  defp put({:replay, off}, config) when off in @off, do: %{config | replay: nil}

  defp put({:replay, module}, config) when is_atom(module) and not is_boolean(module),
    do: %{config | replay: module}

  defp put({:pointer, value}, config),
    do: %{config | pointer: switch(:pointer, value, config.pointer, @pointer, &positive?/2)}

  defp put({:state, value}, config),
    do: %{config | state: switch(:state, value, config.state, @state, &valid_state?/2)}

  defp put({:flush, value}, config),
    do: %{config | flush: switch(:flush, value, config.flush, @flush, &positive?/2)}

  defp put({:export, value}, config),
    do: %{config | export: switch(:export, value, config.export, @export, &valid_export?/2)}

  defp put({:retention, opts}, config) when is_list(opts),
    do: %{config | retention: merge(config.retention, opts, &valid_retention?/2)}

  defp put({:persist, opts}, config) when is_list(opts),
    do: %{config | persist: merge(config.persist, opts, &valid_persist?/2)}

  defp put({key, value}, _config), do: invalid!(key, value)

  defp media(off) when off in @off, do: []
  defp media(true), do: @media

  defp media(settings) when is_list(settings) do
    if settings -- @media == [], do: settings, else: invalid!(:media, settings)
  end

  defp media(settings), do: invalid!(:media, settings)

  # An option that can be off: nil or false switch it off, true turns it on
  # as it was or with the defaults, and a keyword list sets some of it.
  defp switch(_key, off, _current, _defaults, _valid?) when off in @off, do: nil
  defp switch(_key, true, current, defaults, _valid?), do: current || defaults

  defp switch(_key, opts, current, defaults, valid?) when is_list(opts),
    do: merge(current || defaults, opts, valid?)

  defp switch(key, value, _current, _defaults, _valid?), do: invalid!(key, value)

  defp merge(current, opts, valid?) do
    Enum.reduce(opts, current, fn {key, value}, acc ->
      if Map.has_key?(acc, key) and valid?.(key, value),
        do: Map.put(acc, key, value),
        else: invalid!(key, value)
    end)
  end

  defp collector([name | _rest] = event) when is_atom(name),
    do: {PhoenixReplay.Collector.Generic, [event: event]}

  defp collector({[name | _rest] = event, opts}) when is_atom(name) and is_list(opts),
    do: {PhoenixReplay.Collector.Generic, [{:event, event} | opts]}

  defp collector({module, opts}) when is_atom(module) and is_list(opts), do: {module, opts}
  defp collector(module) when is_atom(module), do: {module, []}

  defp collector(entry), do: invalid!(:collect, entry)

  defp pattern(%Regex{} = regex), do: regex
  defp pattern(source) when is_binary(source), do: Regex.compile!(source)

  defp pattern(pattern), do: invalid!(:redact, pattern)

  defp valid_keep?(:rate, value), do: is_number(value) and value >= 0 and value <= 1
  defp valid_keep?(:errors, value), do: is_boolean(value)
  defp valid_keep?(:marks, value), do: is_boolean(value)
  defp valid_keep?(:slower_than, value), do: is_nil(value) or pos_integer?(value)

  defp valid_logs?(:level, value), do: value in Logger.levels()
  defp valid_logs?(:metadata, value), do: is_list(value) and Enum.all?(value, &is_atom/1)
  defp valid_logs?(:limit, value), do: pos_integer?(value)

  defp positive?(_key, value), do: pos_integer?(value)

  defp valid_state?(:inputs, value), do: is_boolean(value)
  defp valid_state?(key, value), do: positive?(key, value)

  defp header(name) when is_binary(name) or is_atom(name) do
    name = name |> to_string() |> String.downcase()

    if name in @secret_headers or name == "",
      do: invalid!(:headers, name),
      else: name
  end

  defp header(name), do: invalid!(:headers, name)

  defp landing(value, current) do
    case switch(:landing, value, current, @landing, &valid_landing?/2) do
      nil -> nil
      landing -> %{landing | params: landing.params |> Enum.flat_map(&param/1) |> Enum.uniq()}
    end
  end

  defp param(preset) when is_map_key(@param_presets, preset), do: @param_presets[preset]
  defp param(name) when is_binary(name) and name != "", do: [name]
  defp param(name), do: invalid!(:params, name)

  defp valid_landing?(:params, value), do: is_list(value)
  defp valid_landing?(:referrer, value), do: is_boolean(value) or value == :full
  defp valid_landing?(:attribution, value), do: value in [:first, :last]
  defp valid_landing?(:timeout, value), do: is_integer(value) and value > 0

  defp invalid!(key, value) do
    raise ArgumentError,
          "invalid :phoenix_replay configuration #{inspect(key)}: #{inspect(value)}"
  end

  defp valid_export?(:endpoint, value), do: is_atom(value)
  defp valid_export?(:frame_layout, nil), do: true
  defp valid_export?(:frame_layout, {module, fun}), do: is_atom(module) and is_atom(fun)
  defp valid_export?(:dir, value), do: is_nil(value) or is_binary(value)
  defp valid_export?(:idle, value), do: is_nil(value) or pos_integer?(value)
  defp valid_export?(key, value) when key in [:crf, :hold], do: non_neg_integer?(value)
  defp valid_export?(key, value) when key in [:preset, :ffmpeg], do: is_binary(value)
  defp valid_export?(:playwright, value), do: Keyword.keyword?(value)
  defp valid_export?(:queue, {module, opts}), do: is_atom(module) and Keyword.keyword?(opts)
  defp valid_export?(:queue, value), do: is_atom(value)
  defp valid_export?(_key, value), do: pos_integer?(value)

  defp valid_retention?(:max_age, value), do: is_nil(value) or pos_integer?(value)
  defp valid_retention?(:max_count, value), do: is_nil(value) or non_neg_integer?(value)
  defp valid_retention?(:interval, value), do: pos_integer?(value)

  defp valid_persist?(:attempts, value), do: pos_integer?(value)
  defp valid_persist?(:backoff, value), do: non_neg_integer?(value)

  defp pos_integer?(value), do: is_integer(value) and value > 0
  defp non_neg_integer?(value), do: is_integer(value) and value >= 0
end
