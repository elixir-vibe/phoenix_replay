defmodule PhoenixReplay.Web.Export.Access do
  @moduledoc """
  Lets the export browser, and nothing else, into `PhoenixReplay.Web.Export.Router`.

  An export signs the recording's id with `PhoenixReplay.Export.Runtime.stage_url/3`;
  the stage and the frame take the token in their path and mount only with
  a valid one for that recording. The secret is made when
  `PhoenixReplay.Web.Export.Endpoint` starts, so tokens die with it.

  It also points the frame at your endpoint for its stylesheet, and
  renders the frame in the `:frame_layout` the `:export` configuration
  names.
  """

  import Phoenix.LiveView, only: [put_private: 3]

  alias PhoenixReplay.Config
  alias PhoenixReplay.Export.Runtime
  alias PhoenixReplay.Web.Export.Endpoint
  alias PhoenixReplay.Web.{Context, Layouts, NotFoundError}

  @private :phoenix_replay_export

  @doc "The id of the recording the stage was opened for."
  @spec recording_id(Phoenix.LiveView.Socket.t()) :: PhoenixReplay.Recording.id()
  def recording_id(%{private: %{@private => id}}), do: id

  @doc """
  Mounts the stage or frame only with a valid token for the recording in
  the path, and points the frame's stylesheet at your endpoint.
  """
  @spec on_mount(:default, map(), map(), Phoenix.LiveView.Socket.t()) ::
          {:cont, Phoenix.LiveView.Socket.t()}
  def on_mount(:default, params, _session, socket) do
    with token when is_binary(token) <- params["token"],
         {:ok, id} <- Runtime.verify(Endpoint, token),
         true <- params["id"] in [nil, id] do
      {:cont,
       socket
       |> put_private(@private, id)
       |> Context.put_endpoint(Config.load().export.endpoint)}
    else
      _invalid -> raise NotFoundError, id: params["id"]
    end
  end

  @doc """
  The root layout of exported frames: the `:frame_layout` the `:export`
  configuration names, or the dashboard's frame layout.
  """
  @spec frame_layout(map()) :: Phoenix.LiveView.Rendered.t()
  def frame_layout(assigns) do
    {module, function} = Config.load().export.frame_layout || {Layouts, :frame}
    apply(module, function, [assigns])
  end
end
