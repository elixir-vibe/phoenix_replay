defmodule Mix.Tasks.PhoenixReplay.Export do
  @shortdoc "Exports a recording, or a visit, as a video"

  @moduledoc """
  #{@shortdoc}, for a bug report or a ticket.

      mix phoenix_replay.export RECORDING_ID [--output replay.mp4] [options]
      mix phoenix_replay.export VISIT_ID [--output visit.mp4] [options]

  It starts your application, exports the recording with
  `PhoenixReplay.Export` as the player's **Export video** does, shows the
  progress, and copies the video to `--output`, by default
  `replay-RECORDING_ID.mp4` in the current directory. Your endpoint need
  not be serving: the export browser loads the replay from an endpoint of
  its own.

  Given a visit's id, a summary's `visit`, it exports each of the visit's
  recordings, in the order they started, and joins them into one video,
  each page fit inside the first one's size. `--from` and `--to` are for a
  single recording.

  Exporting needs the `:export` configuration; see `PhoenixReplay.Export`.

  ## Options

  The same as the player's export dialog, by default as configured; see
  `PhoenixReplay.Export.Options`:

    * `--from SECONDS`, `--to SECONDS` — the range of the recording
    * `--no-skip-idle` — keep stretches without activity whole
    * `--no-pointer` — leave the pointer out
    * `--size recorded|1x|half` — the video's size
    * `--fps 15|30|60` — the frame rate
    * `--quality small|balanced|best` — the trade between size and detail
  """

  use Mix.Task

  alias PhoenixReplay.{Catalog, Config, Export}
  alias PhoenixReplay.Export.{FFmpeg, Options}
  alias PhoenixReplay.Recording.Client

  # Only run once `Export.available/1` found MuonTrap, an optional dependency.
  @compile {:no_warn_undefined, FFmpeg}

  @switches [
    output: :string,
    from: :string,
    to: :string,
    skip_idle: :boolean,
    pointer: :boolean,
    size: :string,
    fps: :string,
    quality: :string
  ]
  @aliases [o: :output]

  @impl true
  def run(args) do
    {opts, ids} = OptionParser.parse!(args, strict: @switches, aliases: @aliases)

    id =
      case ids do
        [id] -> id
        _other -> Mix.raise("Usage: mix phoenix_replay.export RECORDING_ID [--output PATH]")
      end

    output = opts[:output] || "replay-#{id}.mp4"
    Mix.Task.run("app.start")
    config = Config.load()

    with {:error, reason} <- Export.available(config),
         do: Mix.raise("Cannot export videos: " <> Export.describe(reason))

    params =
      opts
      |> Keyword.delete(:output)
      |> Map.new(fn {key, value} -> {to_string(key), to_string(value)} end)

    options =
      case Options.parse(params, config.export) do
        {:ok, options} -> options
        {:error, message} -> Mix.raise(message)
      end

    case Catalog.fetch(config, id) do
      {:ok, _recording} ->
        File.cp!(export(id, config, options), output)
        Mix.shell().info("\rExported #{id} to #{output}")

      {:error, _not_a_recording} ->
        export_visit(id, config, options, output)
    end
  end

  defp export(id, config, options) do
    :ok = Export.subscribe(id)
    {:ok, job} = Export.start(id, config, options)
    job = await(job)

    case job.status do
      :done -> job.path
      :failed -> Mix.raise("Could not export #{id}: #{job.error}")
      :cancelled -> Mix.raise("The export of #{id} was cancelled")
    end
  end

  # Each recording of the visit, then one video of them all.
  defp export_visit(key, config, options, output) do
    pages = Catalog.visit(config, key)
    if pages == [], do: Mix.raise("No recording or visit #{key}")

    if options.from || options.to,
      do: Mix.raise("--from and --to are for a single recording, not a visit")

    paths =
      pages
      |> Enum.with_index(1)
      |> Enum.map(fn {page, number} ->
        Mix.shell().info("\rPage #{number} of #{length(pages)}: #{page.url}")
        export(page.id, config, options)
      end)

    export = Options.apply(options, config.export)
    {width, height} = size(List.first(pages).viewport || Client.default_viewport(), export)

    case FFmpeg.run(
           export.ffmpeg,
           join_args(paths, width, height, export, output),
           & &1,
           export.timeout
         ) do
      :ok -> Mix.shell().info("\rExported visit #{key}, #{length(pages)} pages, to #{output}")
      {:error, reason} -> Mix.raise("Could not join the visit's pages: #{inspect(reason)}")
    end
  end

  # The first page's video size: its viewport at the pixel ratio and scale
  # the export renders at, in even pixels.
  defp size(viewport, export) do
    ratio = min(viewport[:dpr] || 1, export.max_dpr) * export.scale
    {even(viewport.width * ratio), even(viewport.height * ratio)}
  end

  defp even(pixels), do: trunc(pixels / 2) * 2

  # Every page fit inside the first one's size, centered, then joined in order.
  defp join_args(paths, width, height, export, output) do
    fit =
      paths
      |> Enum.with_index()
      |> Enum.map_join(";", fn {_path, index} ->
        "[#{index}:v]scale=#{width}:#{height}:force_original_aspect_ratio=decrease," <>
          "pad=#{width}:#{height}:(ow-iw)/2:(oh-ih)/2,setsar=1[v#{index}]"
      end)

    count = length(paths)
    joined = Enum.map_join(0..(count - 1), &"[v#{&1}]") <> "concat=n=#{count}:v=1:a=0[out]"

    ["-y", "-nostats", "-progress", "pipe:1"] ++
      Enum.flat_map(paths, &["-i", &1]) ++
      ["-filter_complex", fit <> ";" <> joined, "-map", "[out]"] ++
      ["-c:v", "libx264", "-preset", export.preset, "-crf", to_string(export.crf)] ++
      ["-pix_fmt", "yuv420p", "-movflags", "+faststart", output]
  end

  defp await(%{id: id}) do
    receive do
      {Export, %{id: ^id} = job} ->
        report(job)
        if Export.Job.finished?(job), do: job, else: await(job)
    end
  end

  defp report(%{status: :running, progress: progress}),
    do: IO.write("\rExporting… #{progress}%")

  defp report(_job), do: :ok
end
