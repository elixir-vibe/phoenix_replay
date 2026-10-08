defmodule PhoenixReplay.Web.Export.Download do
  @moduledoc """
  Serves an exported video to the player that asked for it.

  The player authorized the viewer when it opened the recording, and
  signs the export's id with your endpoint into the link with `sign/2`;
  the link is good for as long as the video is kept. It sits under the
  dashboard's path, so it is behind your router's pipeline too.

  In a cluster, the download may reach another node than the one that
  queued the export or rendered the video. The link names the node that
  signed it, which `PhoenixReplay.Export.Queue.Local` keeps the job on, and
  the job names the node whose disk the video is on; the video is
  streamed from there over the cluster's connection.
  """

  @behaviour Plug

  import Plug.Conn

  alias PhoenixReplay.Export
  alias PhoenixReplay.Export.{Job, Video}

  @salt "phoenix_replay video"
  # How much of a video is read from another node at a time, and how long
  # that node may take.
  @chunk 1_048_576
  @remote_timeout 15_000

  @doc """
  The token for a link to `job`'s video, signed with the endpoint of
  `context`, a socket, a connection or the endpoint itself.
  """
  @spec sign(Phoenix.Token.context(), Job.t()) :: String.t()
  def sign(context, %Job{id: id}), do: Phoenix.Token.sign(context, @salt, {id, node()})

  @impl true
  def init(opts), do: opts

  @impl true
  def call(%Plug.Conn{path_params: %{"id" => id, "token" => token}} = conn, _opts) do
    max_age = div(PhoenixReplay.Config.load().export.ttl, 1_000)

    with {:ok, {job_id, signed_on}} <- Phoenix.Token.verify(conn, @salt, token, max_age: max_age),
         %Job{status: :done, recording_id: ^id} = job <- find(job_id, signed_on),
         {:ok, conn} <- serve(conn, job) do
      conn
    else
      _missing -> send_resp(conn, 404, "Not found")
    end
  end

  @doc """
  Reads up to `size` bytes of the video at `path` from `offset`, for a node
  serving a video rendered on this one. Only an export's video is read: a
  file in this node's export directory, named as exports name them.
  """
  @spec read_chunk(Path.t(), non_neg_integer(), pos_integer()) ::
          {:ok, binary()} | :eof | {:error, term()}
  def read_chunk(path, offset, size) do
    if video?(path) do
      case File.open(path, [:read, :binary], &:file.pread(&1, offset, size)) do
        {:ok, result} -> result
        {:error, reason} -> {:error, reason}
      end
    else
      {:error, :not_a_video}
    end
  end

  defp video?(path) do
    dir = Video.dir(PhoenixReplay.Config.load().export)
    name = Path.basename(path)

    Path.expand(Path.dirname(path)) == Path.expand(dir) and Path.extname(name) == ".mp4" and
      Job.file?(name)
  end

  # This node's queue knows the job, or the node that signed the link does.
  defp find(job_id, signed_on) do
    with nil when signed_on != node() <- Export.get(job_id),
         do: remote(signed_on, Export, :get, [job_id])
  end

  defp serve(conn, %Job{node: node, path: path}) when node in [nil, node()] do
    if File.exists?(path),
      do: {:ok, conn |> video_headers() |> send_file(200, path)},
      else: :missing
  end

  defp serve(conn, %Job{node: node, path: path}) do
    case remote(node, __MODULE__, :read_chunk, [path, 0, @chunk]) do
      {:ok, first} ->
        conn = conn |> video_headers() |> send_chunked(200)
        {:ok, stream(conn, node, path, first, byte_size(first))}

      _missing ->
        :missing
    end
  end

  # Sends the chunk read, then reads the next, until the end of the file
  # or the client goes away.
  defp stream(conn, node, path, data, offset) do
    case chunk(conn, data) do
      {:ok, conn} ->
        case remote(node, __MODULE__, :read_chunk, [path, offset, @chunk]) do
          {:ok, next} -> stream(conn, node, path, next, offset + byte_size(next))
          _end -> conn
        end

      {:error, _closed} ->
        conn
    end
  end

  defp video_headers(%Plug.Conn{path_params: %{"id" => id}} = conn) do
    conn
    |> put_resp_content_type("video/mp4")
    |> put_resp_header("content-disposition", ~s(attachment; filename="replay-#{id}.mp4"))
  end

  # A node that is gone, or does not answer, has nothing to give.
  defp remote(node, module, function, args) do
    :erpc.call(node, module, function, args, @remote_timeout)
  rescue
    ErlangError -> nil
  end
end
