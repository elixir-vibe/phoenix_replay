defmodule PhoenixReplay.Export.Encoder do
  @moduledoc """
  Encodes captured screenshots into an H.264 MP4 with `ffmpeg`.

  The screenshots go in through ffmpeg's concat demuxer, each with the
  time it lasts, and come out at the schedule's constant frame rate, so a
  picture that does not change is captured once and still fills its
  frames. The size is rounded down to even pixels, as H.264 needs, and
  the index is moved to the front so the video plays while it downloads.
  """

  require Logger

  alias PhoenixReplay.Config
  alias PhoenixReplay.Export.Schedule

  @typedoc "Each screenshot's path and the frames it lasts, in order."
  @type shots :: [{Path.t(), pos_integer()}]

  @typedoc "Called with the share of the video encoded so far, from 0 to 1."
  @type progress :: (float() -> any())

  @doc "Encodes `shots` into `path`, reporting progress."
  @spec run(shots(), Schedule.t(), Path.t(), Config.export(), progress()) ::
          :ok | {:error, term()}
  def run([{first, _frames} | _rest] = shots, schedule, path, export, progress) do
    list = Path.join(Path.dirname(first), "shots.ffconcat")
    File.write!(list, concat(shots, schedule.fps))
    duration_ms = Schedule.duration_ms(schedule)

    port =
      Port.open({:spawn_executable, System.find_executable(export.ffmpeg)}, [
        :binary,
        :exit_status,
        :stderr_to_stdout,
        {:line, 4_096},
        args: args(list, path, duration_ms, schedule.fps, export)
      ])

    await(port, duration_ms, progress, [])
  end

  # The last picture is listed twice: the demuxer gives the last entry no
  # duration, and -t ends the video on time.
  defp concat(shots, fps) do
    {entries, last} =
      Enum.map_reduce(shots, nil, fn {path, frames}, _last ->
        {"file #{quote_path(path)}\nduration #{seconds(frames * 1_000 / fps)}\n", path}
      end)

    ["ffconcat version 1.0\n", entries, "file #{quote_path(last)}\n"]
  end

  defp args(list, path, duration_ms, fps, export) do
    ~w(-y -v error -nostats -progress pipe:1 -f concat -safe 0 -i) ++
      [list, "-t", seconds(duration_ms)] ++
      ["-vf", "fps=#{fps},scale=trunc(iw/2)*2:trunc(ih/2)*2,format=yuv420p"] ++
      ["-c:v", "libx264", "-preset", export.preset, "-crf", Integer.to_string(export.crf)] ++
      ["-movflags", "+faststart", path]
  end

  defp await(port, duration_ms, progress, output) do
    receive do
      {^port, {:data, {:eol, "out_time_us=" <> microseconds}}} ->
        with {done, ""} <- Integer.parse(microseconds),
             do: progress.(min(done / 1_000 / max(duration_ms, 1), 1.0))

        await(port, duration_ms, progress, output)

      {^port, {:data, {_eol, line}}} ->
        await(port, duration_ms, progress, [line | output])

      {^port, {:exit_status, 0}} ->
        :ok

      {PhoenixReplay.Export, :cancel} ->
        stop(port)
        {:error, :cancelled}

      {^port, {:exit_status, status}} ->
        Logger.error([
          "PhoenixReplay: ffmpeg failed:\n" | Enum.intersperse(Enum.reverse(output), "\n")
        ])

        {:error, {:ffmpeg, status}}
    end
  end

  # Closing the port leaves ffmpeg running until it next writes, so it is
  # stopped first.
  defp stop(port) do
    with {:os_pid, os_pid} <- Port.info(port, :os_pid),
         do: System.cmd("kill", [Integer.to_string(os_pid)], stderr_to_stdout: true)

    if Port.info(port), do: Port.close(port)
  end

  defp seconds(ms), do: :erlang.float_to_binary(ms / 1_000, decimals: 6)

  # ffconcat quotes like a shell: in single quotes, with each single quote
  # closed, escaped and reopened.
  defp quote_path(path), do: "'" <> String.replace(path, "'", ~S('\'')) <> "'"
end
