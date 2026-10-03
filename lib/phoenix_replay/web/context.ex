defmodule PhoenixReplay.Web.Context do
  @moduledoc """
  Per-mount dashboard context built from the router options.

  Attached by `PhoenixReplay.Router` as the first `on_mount` hook and kept in
  `socket.private`, so it never mixes with recorded assigns in the frame.
  Authorization happens later, in each view's `mount/3`, so it sees assigns
  set by the host's own hooks.
  """

  import Phoenix.LiveView, only: [put_private: 3]

  alias PhoenixReplay.{Authorization, Config, Recording, Recordings}
  alias PhoenixReplay.Web.NotFoundError

  @type t :: %__MODULE__{
          base_path: String.t(),
          authorize: module() | nil,
          live_socket_path: String.t(),
          config: Config.t()
        }

  @enforce_keys [:base_path, :live_socket_path, :config]
  defstruct [:base_path, :authorize, :live_socket_path, :config]

  @private :phoenix_replay_context

  @doc "Stores the context built from the router options in the socket."
  @spec on_mount(map(), map() | :not_mounted_at_router, map(), Phoenix.LiveView.Socket.t()) ::
          {:cont, Phoenix.LiveView.Socket.t()}
  def on_mount(options, _params, _session, socket) do
    context = struct!(__MODULE__, Map.put(options, :config, Config.load()))
    {:cont, put_private(socket, @private, context)}
  end

  @doc "Returns the context stored by `on_mount/4`."
  @spec fetch(Phoenix.LiveView.Socket.t()) :: t()
  def fetch(%{private: %{@private => context}}), do: context

  @doc "Checks the configured `PhoenixReplay.Authorization` module."
  @spec allowed?(Phoenix.LiveView.Socket.t(), Authorization.action(), Authorization.subject()) ::
          boolean()
  def allowed?(socket, action, subject) do
    Authorization.allowed?(fetch(socket).authorize, action, subject, socket)
  end

  @doc """
  Fetches a recording the viewer may `:view`.

  Raises `PhoenixReplay.Web.NotFoundError` otherwise, so missing and
  forbidden recordings are indistinguishable.
  """
  @spec fetch_recording!(Phoenix.LiveView.Socket.t(), Recording.id()) :: Recording.t()
  def fetch_recording!(socket, id) do
    with {:ok, recording} <- Recordings.fetch(fetch(socket).config, id),
         true <- allowed?(socket, :view, recording) do
      recording
    else
      _not_found -> raise NotFoundError, id: id
    end
  end

  @doc "Joins `segments` onto the dashboard's base path."
  @spec path(t(), [String.t()]) :: String.t()
  def path(%__MODULE__{base_path: base_path}, segments) do
    case Enum.join([String.trim_trailing(base_path, "/") | segments], "/") do
      "" -> "/"
      path -> path
    end
  end
end
