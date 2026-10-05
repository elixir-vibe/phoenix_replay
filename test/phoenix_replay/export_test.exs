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
