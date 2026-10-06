defmodule PhoenixReplay.Export.Encoder do
  @moduledoc """
  Encodes captured screenshots into an H.264 MP4 with `ffmpeg`, which
  `PhoenixReplay.Export.FFmpeg` runs.

  The screenshots go in through ffmpeg's concat demuxer, each with the
  time it lasts, and come out at the schedule's constant frame rate, so a
  picture that does not change is captured once and still fills its
  frames. The size is rounded down to even pixels, as H.264 needs, and
  the index is moved to the front so the video plays while it downloads.
  """

  alias PhoenixReplay.Export.{FFmpeg, Schedule}

  # Only called once `PhoenixReplay.Export.available/1` found MuonTrap.
  @compile {:no_warn_undefined, FFmpeg}

  @typedoc """
  Each screenshot's path and the frames it lasts, in order. The
  screenshots share a directory and have plain names, such as `0.png`,
  so the concat list can name them as they are.
  """
  @type shots :: [{Path.t(), pos_integer()}]

  @typedoc "Called with the share of the video encoded so far, from 0 to 1."
  @type progress :: (float() -> any())

  @doc "Encodes `shots` into `path`, reporting progress."
  @spec run(shots(), Schedule.t(), Path.t(), map(), progress()) ::
          :ok | {:error, FFmpeg.error()}
  def run(shots, schedule, path, export, progress) do
    list = write_list(shots, schedule.fps)
    duration_ms = Schedule.duration_ms(schedule)

    FFmpeg.run(
      System.find_executable(export.ffmpeg),
      args(list, path, duration_ms, schedule.fps, export),
      &progress.(min(&1 / max(duration_ms, 1), 1.0)),
      export.timeout
    )
  end

  # Each screenshot with how long it shows, next to the screenshots. The
  # last one is named again: the demuxer gives the last entry no duration,
  # and -t ends the video on time.
  defp write_list([{first, _frames} | _rest] = shots, fps) do
    {entries, last} =
      Enum.map_reduce(shots, nil, fn {path, frames}, _last ->
        name = Path.basename(path)
        {["file ", name, "\nduration ", seconds(frames * 1_000 / fps), "\n"], name}
      end)

    list = Path.join(Path.dirname(first), "shots.ffconcat")
    File.write!(list, ["ffconcat version 1.0\n", entries, "file ", last, "\n"])
    list
  end

  defp args(list, path, duration_ms, fps, export) do
    List.flatten([
      # Overwrite the output, print only errors, and report progress on
      # stdout for `PhoenixReplay.Export.FFmpeg` to follow.
      ~w(-y -v error -nostats -progress pipe:1),
      # The screenshots, each for its duration.
      ["-f", "concat", "-i", list],
      # As long as the schedule, at its frame rate, at an even size, in the
      # pixel format players expect.
      ["-t", seconds(duration_ms)],
      ["-vf", "fps=#{fps},scale=#{even("iw", export)}:#{even("ih", export)},format=yuv420p"],
      ["-c:v", "libx264", "-preset", export.preset, "-crf", Integer.to_string(export.crf)],
      # The index first, so the video plays while it downloads.
      ["-movflags", "+faststart", path]
    ])
  end

  # A side scaled by the export's `:scale`, rounded down to even pixels.
  defp even(side, export), do: "trunc(#{side}*#{Map.get(export, :scale, 1)}/2)*2"

  defp seconds(ms), do: :erlang.float_to_binary(ms / 1_000, decimals: 6)
end
