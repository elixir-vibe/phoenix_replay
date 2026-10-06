defmodule PhoenixReplay.Export.FFmpegTest do
  use ExUnit.Case, async: true

  import ExUnit.CaptureLog

  alias PhoenixReplay.Export.FFmpeg

  @moduletag :tmp_dir

  # An ffmpeg that reports its progress, then fails.
  defp fake(dir, script) do
    path = Path.join(dir, "ffmpeg")
    File.write!(path, "#!/bin/sh\n" <> script)
    File.chmod!(path, 0o755)
    path
  end

  test "reports progress, and logs what ffmpeg said rather than its reports", %{tmp_dir: dir} do
    report = Enum.map_join(~w(frame=1 fps=30 stream_0_0_q=23.0 bitrate=1kbits/s total_size=48
                               out_time_us=1500000 out_time_ms=1500000 out_time=00:00:01.5
                               dup_frames=0 drop_frames=0 speed=1x progress=continue), "\n", & &1)

    ffmpeg =
      fake(dir, """
      echo "[libx264 @ 0x1] broken: the encoder gave up"
      for i in 1 2 3 4 5; do printf '%s\\n' "#{report}"; done
      exit 1
      """)

    parent = self()

    log =
      capture_log(fn ->
        assert {:error, {:ffmpeg, 1}} = FFmpeg.run(ffmpeg, [], &send(parent, {:done, &1}), 5_000)
      end)

    assert_received {:done, 1_500}
    assert log =~ "the encoder gave up"
    refute log =~ "frame="
    refute log =~ "stream_0_0_q"
  end
end
