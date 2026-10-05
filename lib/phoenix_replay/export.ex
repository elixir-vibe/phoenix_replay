defmodule PhoenixReplay.Export do
  @moduledoc """
  Exports recordings as videos of the replayed page and the pointer.

  A recording holds no pixels: the player renders it again from recorded
  assigns. An export does the same in a headless browser and films it.

    1. `PhoenixReplay.Export.Schedule` plans the video: a constant frame
       rate from the first render, idle stretches shortened, and a
       screenshot only where the picture changes.
    2. `PhoenixReplay.Export.Capture` loads the replay into Chromium through
       [`playwright_ex`](https://hexdocs.pm/playwright_ex), at the recorded
       viewport and pixel ratio, steps it through the plan with the
       player's own pointer overlay, and screenshots each change.
    3. `PhoenixReplay.Export.Encoder` encodes the screenshots with `ffmpeg`
       into an H.264 MP4.

  The browser loads the replay from `PhoenixReplay.Export.Endpoint`, a
  private endpoint on 127.0.0.1 started with the first export, so it
  needs no route or login in your app.

  Exports run one at a time, or `:max_concurrency` at once, under
  `PhoenixReplay.Export.Server`, which broadcasts each job's progress;
  the player's **Export video** and `mix phoenix_replay.export` both use
  it. Finished videos are deleted after `:ttl`.

  ## Setup

  Add `{:playwright_ex, "~> 0.14"}`, install Playwright's Chromium
  (`npx playwright install chromium`) and `ffmpeg`, and name your
  endpoint:

      config :phoenix_replay, export: [endpoint: MyAppWeb.Endpoint]

  See `:export` in `PhoenixReplay.Config` for the other options. Only
  saved recordings are exported, not sessions still running.
  """

  alias PhoenixReplay.Config
  alias PhoenixReplay.Export.{Job, Server}
  alias PhoenixReplay.Recording

  @typedoc "Why exporting is not possible."
  @type unavailable :: :disabled | :no_endpoint | :no_playwright | :no_ffmpeg

  @doc "Whether videos can be exported with `config`, or why not."
  @spec available(Config.t()) :: :ok | {:error, unavailable()}
  def available(%Config{export: nil}), do: {:error, :disabled}
  def available(%Config{export: %{endpoint: nil}}), do: {:error, :no_endpoint}

  def available(%Config{export: export}) do
    cond do
      not Code.ensure_loaded?(PlaywrightEx) -> {:error, :no_playwright}
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
  def describe(:no_ffmpeg), do: "install ffmpeg, or set its path in the :export config"

  @doc """
  Exports a saved recording, or returns the export of it already queued
  or running.
  """
  @spec start(Recording.id(), Config.t()) :: {:ok, Job.t()} | {:error, unavailable()}
  def start(recording_id, config \\ Config.load()) do
    with :ok <- available(config), do: Server.start(recording_id, config)
  end

  @doc """
  Cancels an export that is queued or running. A running one closes its
  browser and stops encoding first, and ends `:cancelled`.
  """
  @spec cancel(Job.id()) :: :ok
  defdelegate cancel(id), to: Server

  @doc "The export with `id`, if it is still kept."
  @spec get(Job.id()) :: Job.t() | nil
  defdelegate get(id), to: Server

  @doc "The latest export of a recording, if one is kept."
  @spec latest(Recording.id()) :: Job.t() | nil
  defdelegate latest(recording_id), to: Server

  @doc """
  Subscribes the caller to the exports of a recording: each change to one
  arrives as `{PhoenixReplay.Export, %PhoenixReplay.Export.Job{}}`.
  """
  @spec subscribe(Recording.id()) :: :ok | {:error, term()}
  defdelegate subscribe(recording_id), to: Server
end
