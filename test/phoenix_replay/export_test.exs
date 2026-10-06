defmodule PhoenixReplay.ExportTest do
  # Real exports: Chromium films the replay and ffmpeg encodes it.
  use ExUnit.Case, async: false

  import Phoenix.ConnTest
  import Phoenix.LiveViewTest

  alias PhoenixReplay.{Export, Storage}
  alias PhoenixReplay.Export.{Job, Video}
  alias PhoenixReplay.Test.Fixtures

  @endpoint PhoenixReplay.Test.Endpoint
  @moduletag :export
  @moduletag timeout: 120_000

  setup do
    recording = Fixtures.counter_recording(clicks: 1)
    :ok = Storage.save(Fixtures.storage(), recording)
    on_exit(fn -> Storage.delete(Fixtures.storage(), recording.id) end)
    :ok = Export.subscribe(recording.id)
    %{recording: recording}
  end

  defp finished(%Job{id: id}) do
    receive do
      {Export, %Job{id: ^id} = job} -> if Job.finished?(job), do: job, else: finished(job)
    after
      60_000 -> flunk("the export did not finish")
    end
  end

  test "exports a saved recording as an H.264 video", %{recording: recording} do
    {:ok, job} = Export.start(recording.id)
    # A second request while it runs gets the same export.
    assert {:ok, %Job{id: same}} = Export.start(recording.id)
    assert same == job.id

    assert %Job{status: :done, progress: 100, path: path} = finished(job)
    assert Export.latest(recording.id).id == job.id
    assert <<_size::32, "ftyp", _rest::binary>> = File.read!(path)

    {probe, 0} =
      System.cmd("ffprobe", [
        "-i",
        path
        | ~w(-v error -show_entries stream=codec_name,width,height,avg_frame_rate -show_entries format=duration -of default=noprint_wrappers=1)
      ])

    assert probe =~ "codec_name=h264"
    assert probe =~ "avg_frame_rate=10/1"
    # The default 1280 × 800 at a pixel ratio of 1: the recording has no viewport.
    assert probe =~ "width=1280"
    assert probe =~ "height=800"
    # From the first render at 5 ms to the click's render at 1001 ms, then
    # the hold of 500 ms.
    assert probe =~ "duration=1.4"
  end

  test "cancels a running export, leaving no files behind" do
    recording = Fixtures.counter_recording(clicks: 10)
    :ok = Storage.save(Fixtures.storage(), recording)
    on_exit(fn -> Storage.delete(Fixtures.storage(), recording.id) end)
    :ok = Export.subscribe(recording.id)
    {:ok, %Job{id: id} = job} = Export.start(recording.id)

    # Once it has screenshots to throw away.
    assert_receive {Export, %Job{id: ^id, status: :running, progress: progress}}
                   when progress > 0,
                   30_000

    :ok = Export.cancel(id)
    assert %Job{status: :cancelled, path: nil} = finished(job)

    dir = Video.dir(PhoenixReplay.Config.load().export)
    refute File.exists?(Path.join(dir, id))
    refute File.exists?(Path.join(dir, id <> ".mp4"))
  end

  test "cancels a queued export without running it", %{recording: recording} do
    other = Fixtures.counter_recording()
    :ok = Storage.save(Fixtures.storage(), other)
    on_exit(fn -> Storage.delete(Fixtures.storage(), other.id) end)
    :ok = Export.subscribe(other.id)

    {:ok, running} = Export.start(recording.id)
    {:ok, %Job{status: :queued} = queued} = Export.start(other.id)
    :ok = Export.cancel(queued.id)

    assert %Job{status: :cancelled} = finished(queued)
    assert %Job{status: :done} = finished(running)
    assert Export.get(queued.id).status == :cancelled
  end

  test "refuses an export that would take more screenshots than allowed", %{recording: recording} do
    config = PhoenixReplay.Config.load(export: [max_shots: 1])
    {:ok, job} = Export.start(recording.id, config)

    assert %Job{status: :failed, error: "The video would take " <> rest} = finished(job)
    assert rest =~ "more than the 1 allowed"
  end

  test "deletes what a stopped server left in the export directory, once it is old" do
    dir = Video.dir(PhoenixReplay.Config.load().export)
    File.mkdir_p!(dir)
    two_hours_ago = System.os_time(:second) - 2 * 3_600
    old = Path.join(dir, "Lft-BehindVideo0.mp4")
    old_shots = Path.join(dir, "Lft-BehindShots0")
    fresh = Path.join(dir, "AnotherVmVideo00.mp4")
    # Not an export's: the directory may be shared.
    other = Path.join(dir, "notes.txt")
    File.mkdir_p!(old_shots)
    for path <- [old, fresh, other], do: File.write!(path, "")
    for path <- [old, old_shots, other], do: File.touch!(path, two_hours_ago)

    :ok =
      Supervisor.terminate_child(
        PhoenixReplay.Export.Supervisor,
        PhoenixReplay.Export.Queue.Local
      )

    {:ok, _pid} =
      Supervisor.restart_child(PhoenixReplay.Export.Supervisor, PhoenixReplay.Export.Queue.Local)

    refute File.exists?(old)
    refute File.exists?(old_shots)
    assert File.exists?(fresh)
    assert File.exists?(other)
    for path <- [fresh, other], do: File.rm(path)
  end

  test "stops ffmpeg when it goes quiet for longer than the timeout" do
    dir = Path.join(System.tmp_dir!(), "phoenix_replay_encoder_test")
    File.mkdir_p!(dir)
    on_exit(fn -> File.rm_rf(dir) end)
    shot = Path.join(dir, "0.png")

    {_out, 0} =
      System.cmd("ffmpeg", [
        "-v",
        "error",
        "-y",
        "-f",
        "lavfi",
        "-i",
        "color=red:s=64x64",
        "-frames:v",
        "1",
        shot
      ])

    schedule = %PhoenixReplay.Export.Schedule{
      shots: [],
      canvas: %{width: 64, height: 64},
      dpr: 1,
      fps: 30
    }

    # Ten minutes of video at the slowest preset: no progress within 1 ms.
    export = %{PhoenixReplay.Config.load().export | timeout: 1, preset: "veryslow"}

    schedule = %{
      schedule
      | shots: [%{index: 0, at: 0, viewport: %{width: 64, height: 64}, frames: 18_000}]
    }

    assert {:error, {:ffmpeg, :timeout}} =
             PhoenixReplay.Export.Encoder.run(
               [{shot, 18_000}],
               schedule,
               Path.join(dir, "out.mp4"),
               export,
               fn _ -> :ok end
             )
  end

  test "stops an ffmpeg that never reports progress" do
    dir = Path.join(System.tmp_dir!(), "phoenix_replay_stuck_ffmpeg")
    File.mkdir_p!(dir)
    on_exit(fn -> File.rm_rf(dir) end)
    pid_file = Path.join(dir, "pid")
    stuck = Path.join(dir, "ffmpeg")
    # Never reports progress.
    File.write!(stuck, "#!/bin/sh\necho $$ > #{pid_file}\nexec sleep 60\n")
    File.chmod!(stuck, 0o755)

    shot = %{index: 0, at: 0, viewport: %{width: 64, height: 64}, frames: 1}

    schedule = %PhoenixReplay.Export.Schedule{
      shots: [shot],
      canvas: %{width: 64, height: 64},
      dpr: 1,
      fps: 30
    }

    # Long enough for the script to start and write its pid on a busy machine.
    export = %{PhoenixReplay.Config.load().export | ffmpeg: stuck, timeout: 3_000}

    assert {:error, {:ffmpeg, :timeout}} =
             PhoenixReplay.Export.Encoder.run(
               [{Path.join(dir, "0.png"), 1}],
               schedule,
               Path.join(dir, "out.mp4"),
               export,
               fn _progress -> :ok end
             )

    # MuonTrap stops it once its port closes, a moment after.
    os_pid = pid_file |> File.read!() |> String.trim()
    assert stopped?(os_pid, 40), "ffmpeg #{os_pid} is still running"
  end

  defp stopped?(_os_pid, 0), do: false

  defp stopped?(os_pid, tries) do
    case System.cmd("kill", ["-0", os_pid], stderr_to_stdout: true) do
      {_out, 0} ->
        Process.sleep(50)
        stopped?(os_pid, tries - 1)

      {_out, _status} ->
        true
    end
  end

  test "fails a recording that is not saved" do
    :ok = Export.subscribe("missing")
    {:ok, job} = Export.start("missing")
    assert %Job{status: :failed, error: "The recording no longer exists."} = finished(job)
  end

  defp probe(path) do
    {probe, 0} =
      System.cmd("ffprobe", [
        "-i",
        path
        | ~w(-v error -show_entries stream=width,height,avg_frame_rate -show_entries format=duration -of default=noprint_wrappers=1)
      ])

    probe
  end

  test "the player exports and links the video", %{recording: recording} do
    {:ok, view, _html} = live(build_conn(), "/replay/#{recording.id}")

    view |> element("#replay-export") |> render_click()
    assert has_element?(view, "#replay-export-dialog [role=dialog]")
    view |> element("#replay-export-form") |> render_submit(%{"export" => %{}})
    refute has_element?(view, "#replay-export-dialog")
    assert has_element?(view, "#replay-export-status")

    finished(Export.latest(recording.id))
    href = view |> element("#replay-export-download") |> render() |> attribute("href")

    conn = get(build_conn(), href)
    assert conn.status == 200
    assert ["video/mp4" <> _charset] = Plug.Conn.get_resp_header(conn, "content-type")
    assert [disposition] = Plug.Conn.get_resp_header(conn, "content-disposition")
    assert disposition =~ ~s(filename="replay-#{recording.id}.mp4")

    # The link is signed for this recording's video alone.
    assert get(build_conn(), String.replace(href, recording.id, "other")).status == 404
    [prefix, _token] = String.split(href, "/video/")
    assert get(build_conn(), prefix <> "/video/forged").status == 404
  end

  test "exports with the options the dialog chose", %{recording: recording} do
    {:ok, view, _html} = live(build_conn(), "/replay/#{recording.id}")
    view |> element("#replay-export") |> render_click()

    # A range the wrong way round is explained, and the dialog stays.
    view
    |> element("#replay-export-form")
    |> render_submit(%{"export" => %{"from" => "1", "to" => "0.5"}})

    assert has_element?(view, "#replay-export-error", "From must come before To.")

    view
    |> element("#replay-export-form")
    |> render_submit(%{
      "export" => %{"from" => "0.5", "to" => "", "size" => "half", "fps" => "15"}
    })

    assert %Job{options: %{fps: 15, size: :half, from: 500}} = Export.latest(recording.id)
    assert %Job{status: :done, path: path} = finished(Export.latest(recording.id))

    probe = probe(path)
    assert probe =~ "width=640"
    assert probe =~ "height=400"
    assert probe =~ "avg_frame_rate=15/1"
    # From 0.5 s to the click's render at 1001 ms, then the hold of 500 ms.
    assert probe =~ "duration=1.0"
  end

  test "mix phoenix_replay.export writes the video where asked", %{recording: recording} do
    output = Path.join(System.tmp_dir!(), "phoenix_replay_export_#{recording.id}.mp4")
    on_exit(fn -> File.rm(output) end)

    ExUnit.CaptureIO.capture_io(fn ->
      Mix.Tasks.PhoenixReplay.Export.run([
        recording.id,
        "--output",
        output,
        "--fps",
        "15",
        "--no-pointer"
      ])
    end)

    assert <<_size::32, "ftyp", _rest::binary>> = File.read!(output)
    assert probe(output) =~ "avg_frame_rate=15/1"

    assert_raise Mix.Error, "The frame rate must be one of 15, 30, 60.", fn ->
      Mix.Tasks.PhoenixReplay.Export.run([recording.id, "--fps", "24"])
    end
  end

  defp attribute(html, name) do
    [value] = html |> LazyHTML.from_fragment() |> LazyHTML.query("a") |> LazyHTML.attribute(name)
    value
  end
end
