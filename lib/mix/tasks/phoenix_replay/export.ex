defmodule Mix.Tasks.PhoenixReplay.Export do
  @shortdoc "Exports a recording as a video"

  @moduledoc """
  #{@shortdoc}, for a bug report or a ticket.

      mix phoenix_replay.export RECORDING_ID [--output replay.mp4]

  It starts your application, exports the recording with
  `PhoenixReplay.Export` as the player's **Export video** does, shows the
  progress, and copies the video to `--output`, by default
  `replay-RECORDING_ID.mp4` in the current directory. Your endpoint need
  not be serving: the export browser loads the replay from an endpoint of
  its own.

  Exporting needs the `:export` configuration; see `PhoenixReplay.Export`.
  """

  use Mix.Task

  alias PhoenixReplay.{Config, Export}

  @switches [output: :string]
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

    :ok = Export.subscribe(id)
    {:ok, job} = Export.start(id, config)
    job = await(job)

    case job.status do
      :done ->
        File.cp!(job.path, output)
        Mix.shell().info("\rExported #{id} to #{output}")

      :failed ->
        Mix.raise("Could not export #{id}: #{job.error}")

      :cancelled ->
        Mix.raise("The export of #{id} was cancelled")
    end
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
