defmodule PhoenixReplay.Export do
  @moduledoc """
  Exports recordings as videos of the replayed page and the pointer.

  A recording holds no pixels: the player renders it again from recorded
  assigns. An export does the same in a headless browser and films it.

    1. `PhoenixReplay.Export.Schedule` plans the video: a constant frame
       rate from the first render, idle stretches shortened, and a
       screenshot only where the picture changes.
    2. `PhoenixReplay.Export.Screenshots` loads the replay into Chromium through
       [`playwright_ex`](https://hexdocs.pm/playwright_ex), at the recorded
       viewport and pixel ratio, steps it through the plan with the
       player's own pointer overlay, and screenshots each change.
    3. `PhoenixReplay.Export.Encoder` encodes the screenshots with `ffmpeg`
       into an H.264 MP4, run by [MuonTrap](https://hexdocs.pm/muontrap) so it
       never outlives the export.

  The browser loads the replay from `PhoenixReplay.Web.Export.Endpoint`, a
  private endpoint on 127.0.0.1 started with the first export, so it
  needs no route or login in your app.

  Exports wait their turn in a `PhoenixReplay.Export.Queue`: by default
  `PhoenixReplay.Export.Queue.Local`, in memory, one at a time or
  `:max_concurrency` at once; or `PhoenixReplay.Export.Queue.Oban`, in
  your Oban queue. Each job's progress is broadcast; the player's **Export
  video** and `mix phoenix_replay.export` both follow it. Finished videos
  are deleted after `:ttl`.

  ## Setup

  Add `{:playwright_ex, "~> 0.14"}` and `{:muontrap, "~> 1.6"}`, install
  Playwright's Chromium (`npx playwright install chromium`) and `ffmpeg`,
  and name your endpoint. MuonTrap runs on Linux and macOS.

      config :phoenix_replay, export: [endpoint: MyAppWeb.Endpoint]

  See `:export` in `PhoenixReplay.Config` for the other options. Only
  saved recordings are exported, not sessions still running.
  """

  alias PhoenixReplay.Config
  alias PhoenixReplay.Export.{Job, Options, Queue}
  alias PhoenixReplay.Recording

  @typedoc "Why exporting is not possible."
  @type unavailable :: :disabled | :no_endpoint | :no_playwright | :no_muontrap | :no_ffmpeg

  @doc "Whether videos can be exported with `config`, or why not."
  @spec available(Config.t()) :: :ok | {:error, unavailable()}
  def available(%Config{export: nil}), do: {:error, :disabled}
  def available(%Config{export: %{endpoint: nil}}), do: {:error, :no_endpoint}

  def available(%Config{export: export}) do
    cond do
      not Code.ensure_loaded?(PlaywrightEx) -> {:error, :no_playwright}
      not Code.ensure_loaded?(MuonTrap) -> {:error, :no_muontrap}
      System.find_executable(export.ffmpeg) == nil -> {:error, :no_ffmpeg}
      true -> :ok
    end
  end

  @doc "Whether videos can be exported with `config`."
  @spec available?(Config.t()) :: boolean()
  def available?(config), do: available(config) == :ok

  @doc "Explains why exporting is not possible."
  @spec describe(unavailable()) :: String.t()
  def describe(:disabled), do: "video export is off; set :export in the :phoenix_replay config"

  def describe(:no_endpoint),
    do: "set your endpoint in the :export config: export: [endpoint: ...]"

  def describe(:no_playwright), do: "add {:playwright_ex, \"~> 0.14\"} to your dependencies"
  def describe(:no_muontrap), do: "add {:muontrap, \"~> 1.6\"} to your dependencies"
  def describe(:no_ffmpeg), do: "install ffmpeg, or set its path in the :export config"

  @doc """
  Exports a saved recording with `options`, by default those the
  configuration sets, or returns the export of it already queued or
  running. See `PhoenixReplay.Export.Options`.
  """
  @spec start(Recording.id(), Config.t(), Options.t() | nil) ::
          {:ok, Job.t()} | {:error, unavailable()}
  def start(recording_id, config \\ Config.load(), options \\ nil) do
    with :ok <- available(config) do
      {queue, opts} = Queue.of(config)
      queue.start(recording_id, config, options || Options.new(config.export), opts)
    end
  end

  @doc """
  Cancels an export that is queued or running. A running one closes its
  browser and stops encoding first, and ends `:cancelled`.
  """
  @spec cancel(Job.id(), Config.t()) :: :ok
  def cancel(id, config \\ Config.load()) do
    {queue, opts} = Queue.of(config)
    queue.cancel(id, opts)
  end

  @doc "The export with `id`, if it is still kept."
  @spec get(Job.id(), Config.t()) :: Job.t() | nil
  def get(id, config \\ Config.load()) do
    {queue, opts} = Queue.of(config)
    queue.get(id, opts)
  end

  @doc "The latest export of a recording, if one is kept."
  @spec latest(Recording.id(), Config.t()) :: Job.t() | nil
  def latest(recording_id, config \\ Config.load()) do
    {queue, opts} = Queue.of(config)
    queue.latest(recording_id, opts)
  end

  @doc """
  Subscribes the caller to the exports of a recording: each change to one
  arrives as `{PhoenixReplay.Export, %PhoenixReplay.Export.Job{}}`.
  """
  @spec subscribe(Recording.id()) :: :ok | {:error, term()}
  defdelegate subscribe(recording_id), to: Queue
end
