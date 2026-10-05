defmodule PhoenixReplay.Web.Download do
  @moduledoc """
  Serves an exported video to the player that asked for it.

  The player authorized the viewer when it opened the recording, and
  signs the export's id with your endpoint into the link with `sign/2`;
  the link is good for as long as the video is kept. It sits under the
  dashboard's path, so it is behind your router's pipeline too.
  """

  @behaviour Plug

  import Plug.Conn

  alias PhoenixReplay.Export
  alias PhoenixReplay.Export.Job

  @salt "phoenix_replay video"

  @doc "The token for a link to `job`'s video, signed with the socket's endpoint."
  @spec sign(Phoenix.LiveView.Socket.t(), Job.t()) :: String.t()
  def sign(socket, %Job{id: id}), do: Phoenix.Token.sign(socket, @salt, id)

  @impl true
  def init(opts), do: opts

  @impl true
  def call(%Plug.Conn{path_params: %{"id" => id, "token" => token}} = conn, _opts) do
    max_age = div(PhoenixReplay.Config.load().export.ttl, 1_000)

    with {:ok, job_id} <- Phoenix.Token.verify(conn, @salt, token, max_age: max_age),
         %Job{status: :done, recording_id: ^id, path: path} <- Export.get(job_id),
         true <- File.exists?(path) do
      conn
      |> put_resp_content_type("video/mp4")
      |> put_resp_header("content-disposition", ~s(attachment; filename="replay-#{id}.mp4"))
      |> send_file(200, path)
    else
      _missing -> send_resp(conn, 404, "Not found")
    end
  end
end
