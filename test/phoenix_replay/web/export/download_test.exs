defmodule PhoenixReplay.Web.Export.DownloadTest do
  # It swaps the export queue in the application environment.
  use ExUnit.Case, async: false

  import Phoenix.ConnTest

  alias PhoenixReplay.Export.Job
  alias PhoenixReplay.Web.Export.Download

  @endpoint PhoenixReplay.Test.Endpoint

  # A queue that knows the jobs a test gives it.
  defmodule Jobs do
    @behaviour PhoenixReplay.Export.Queue

    def put(%Job{} = job), do: :persistent_term.put({__MODULE__, job.id}, job)

    @impl true
    def get(id, _opts), do: :persistent_term.get({__MODULE__, id}, nil)

    @impl true
    def start(_recording_id, _config, _options, _opts), do: raise("not used")
    @impl true
    def cancel(_id, _opts), do: :ok
    @impl true
    def latest(_recording_id, _opts), do: nil
  end

  @moduletag :tmp_dir

  # A video where exports keep theirs, named as they name them.
  defp video(id, content) do
    dir = PhoenixReplay.Export.Video.dir(PhoenixReplay.Config.load().export)
    File.mkdir_p!(dir)
    path = Path.join(dir, id <> ".mp4")
    File.write!(path, content)
    on_exit(fn -> File.rm(path) end)
    path
  end

  setup do
    export = Application.fetch_env!(:phoenix_replay, :export)
    Application.put_env(:phoenix_replay, :export, Keyword.put(export, :queue, Jobs))
    on_exit(fn -> Application.put_env(:phoenix_replay, :export, export) end)
  end

  defp job(id, path, node) do
    job = %Job{
      id: id,
      recording_id: "rec",
      options: nil,
      status: :done,
      path: path,
      node: node
    }

    Jobs.put(job)
    job
  end

  defp download(job), do: get(build_conn(), "/replay/rec/video/" <> Download.sign(@endpoint, job))

  test "reads an export's video in chunks, for a node serving it, and nothing else",
       %{tmp_dir: dir} do
    path = video("oban-9001", "0123456789")

    assert Download.read_chunk(path, 0, 4) == {:ok, "0123"}
    assert Download.read_chunk(path, 8, 4) == {:ok, "89"}
    assert Download.read_chunk(path, 10, 4) == :eof
    assert {:error, :enoent} = Download.read_chunk(Path.rootname(path) <> "2.mp4", 0, 4)

    # Not a file an export made, or not in the export directory.
    other = Path.join(dir, "oban-9001.mp4")
    File.write!(other, "secret")
    assert Download.read_chunk(other, 0, 4) == {:error, :not_a_video}

    assert Download.read_chunk(Path.join(Path.dirname(path), "notes.txt"), 0, 4) ==
             {:error, :not_a_video}

    assert Download.read_chunk(Path.join(Path.dirname(path), "../oban-9001.mp4"), 0, 4) ==
             {:error, :not_a_video}
  end

  test "sends a video on this node's disk", %{tmp_dir: dir} do
    path = Path.join(dir, "here.mp4")
    File.write!(path, "a video")

    conn = download(job("here", path, node()))
    assert conn.status == 200
    assert conn.resp_body == "a video"
  end

  test "finds nothing on a node that is gone", %{tmp_dir: dir} do
    assert download(job("gone", Path.join(dir, "gone.mp4"), :gone@nowhere)).status == 404
  end

  describe "in a cluster" do
    @describetag :cluster

    setup do
      {:ok, peer, other} =
        :peer.start_link(%{
          name: :"replay_peer_#{System.unique_integer([:positive])}",
          args: Enum.flat_map(:code.get_path(), &[~c"-pa", &1])
        })

      on_exit(fn -> catch_exit(:peer.stop(peer)) end)

      # Configured as this node is, as the nodes of one app are.
      :ok =
        :erpc.call(other, Application, :put_all_env, [
          [phoenix_replay: Application.get_all_env(:phoenix_replay)]
        ])

      %{other: other}
    end

    test "streams a video rendered on another node", %{other: other} do
      # The peer shares this machine's disk; the video is read through it.
      video = :crypto.strong_rand_bytes(2_500_000)
      path = video("oban-9002", video)

      conn = download(job("there", path, other))
      assert conn.status == 200
      assert conn.resp_body == video
      assert ["video/mp4" <> _charset] = Plug.Conn.get_resp_header(conn, "content-type")
    end
  end
end
