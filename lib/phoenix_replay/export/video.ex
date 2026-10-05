defmodule PhoenixReplay.Export.Video do
  @moduledoc """
  Renders one video export: plans it, captures the screenshots, encodes
  them, and leaves the video in the export directory.

  Capturing takes most of the time, so it reports up to 90% of the
  progress and encoding the rest. The screenshots are deleted whatever
  happens, and the video too unless it was finished. Sent
  `{PhoenixReplay.Export, :cancel}`, capturing and encoding stop and the
  render ends with `{:error, :cancelled}`.
  """

  alias PhoenixReplay.{Catalog, Config, Recording}
  alias PhoenixReplay.Export.{Capture, Encoder, Job, Options, Runtime, Schedule}
  alias PhoenixReplay.Recording.{PointerTrack, Timeline}

  @captured 0.9

  @doc "Renders the video of `job`'s recording, reporting progress from 0 to 1."
  @spec render(Job.t(), Config.t(), (float() -> any())) :: {:ok, Path.t()} | {:error, term()}
  def render(%Job{id: id, recording_id: recording_id} = job, %Config{} = config, progress) do
    export = Options.apply(job.options, config.export)
    dir = dir(export)
    shots = Path.join(dir, id)
    video = Path.join(dir, id <> ".mp4")
    File.mkdir_p!(shots)

    try do
      with {:ok, recording} <- fetch(config, recording_id),
           schedule = plan(recording, export, job.options),
           :ok <- bounded(schedule, export.max_shots),
           {:ok, runtime} <- Runtime.ensure(config.export),
           {:ok, list} <-
             Capture.run(
               runtime,
               recording_id,
               schedule,
               shots,
               export,
               job.options,
               &progress.(&1 * @captured)
             ),
           :ok <-
             Encoder.run(
               list,
               schedule,
               video,
               export,
               &progress.(@captured + &1 * (1 - @captured))
             ) do
        {:ok, video}
      else
        error ->
          File.rm(video)
          error
      end
    after
      File.rm_rf(shots)
    end
  end

  @doc "Describes why an export failed, for the people who asked for it."
  @spec describe_error(term()) :: String.t()
  def describe_error(:not_found), do: "The recording no longer exists."
  def describe_error(:running), do: "The session is still running. Export it once it ends."
  def describe_error(:empty), do: "The recording has nothing to show."
  def describe_error(:cancelled), do: "The export was cancelled."
  def describe_error({:browser, message}), do: "The browser failed: #{message}"
  def describe_error({:ffmpeg, :timeout}), do: "ffmpeg stopped responding."
  def describe_error({:ffmpeg, status}), do: "ffmpeg failed with exit status #{status}."

  def describe_error({:too_long, shots, max}),
    do:
      "The video would take #{shots} screenshots, more than the #{max} allowed. " <>
        "Export a shorter range, at a lower frame rate or without the pointer."

  def describe_error(reason), do: "The export failed: #{inspect(reason)}"

  @doc "The directory videos are kept in."
  @spec dir(map()) :: Path.t()
  def dir(%{dir: nil}), do: Path.join(System.tmp_dir!(), "phoenix_replay/exports")
  def dir(%{dir: dir}), do: dir

  # Running sessions are only in the buffer, unredacted.
  defp fetch(config, id) do
    if Catalog.live?(id), do: {:error, :running}, else: saved(Catalog.fetch(config, id))
  end

  defp saved({:ok, %Recording{events: []}}), do: {:error, :empty}
  defp saved({:ok, recording}), do: {:ok, recording}
  defp saved({:error, _reason}), do: {:error, :not_found}

  # Each screenshot is a file until the video is encoded.
  defp bounded(%Schedule{shots: shots}, max) do
    case length(shots) do
      count when count > max -> {:error, {:too_long, count, max}}
      _count -> :ok
    end
  end

  # Rotated, the pointer and the scrolling fit only the recorded layout;
  # without the pointer the page still scrolls as recorded.
  defp plan(recording, export, %Options{} = options) do
    {playback, track} = Timeline.for_playback(recording)

    track =
      cond do
        options.rotated -> PointerTrack.empty()
        options.pointer -> track
        true -> %{track | moves: [], presses: []}
      end

    opts =
      export
      |> Map.take([:fps, :idle, :max_dpr, :hold])
      |> Map.merge(Map.take(options, [:from, :to, :rotated]))
      |> Keyword.new()

    Schedule.new(playback, track, opts)
  end
end
