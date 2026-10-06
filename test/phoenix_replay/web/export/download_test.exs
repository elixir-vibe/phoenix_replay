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

  test "reads a video in chunks, for a node serving it", %{tmp_dir: dir} do
    path = Path.join(dir, "video.mp4")
    File.write!(path, "0123456789")

    assert Download.read_chunk(path, 0, 4) == {:ok, "0123"}
    assert Download.read_chunk(path, 8, 4) == {:ok, "89"}
    assert Download.read_chunk(path, 10, 4) == :eof
    assert {:error, :enoent} = Download.read_chunk(Path.join(dir, "gone.mp4"), 0, 4)
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
      %{other: other}
    end

    test "streams a video rendered on another node", %{tmp_dir: dir, other: other} do
      # The peer shares this machine's disk; the video is read through it.
      path = Path.join(dir, "there.mp4")
      video = :crypto.strong_rand_bytes(2_500_000)
      File.write!(path, video)

      conn = download(job("there", path, other))
      assert conn.status == 200
      assert conn.resp_body == video
      assert ["video/mp4" <> _charset] = Plug.Conn.get_resp_header(conn, "content-type")
    end
  end
end
