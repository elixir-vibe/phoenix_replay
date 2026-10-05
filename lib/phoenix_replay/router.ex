defmodule PhoenixReplay.Router do
  @moduledoc """
  Mounts the PhoenixReplay dashboard in a Phoenix router.

      defmodule MyAppWeb.Router do
        use Phoenix.Router
        import PhoenixReplay.Router

        scope "/admin" do
          pipe_through [:browser, :require_admin]

          phoenix_replay "/replay",
            on_mount: [{MyAppWeb.UserAuth, :ensure_admin}],
            authorize: MyApp.ReplayAuthorization
        end
      end

  ## Options

    * `:on_mount` — hooks run before the dashboard's own, typically
      authentication that assigns the current user
    * `:authorize` — a `PhoenixReplay.Authorization` module
    * `:frame_layout` — `{module, function}` root layout for the replay frame,
      which renders your recorded views. Defaults to a layout that loads your
      endpoint's `/assets/css/app.css`
    * `:live_socket_path` — your endpoint's LiveView socket path
      (default `"/live"`)
    * `:as` — live session name prefix, needed only when mounting the
      dashboard more than once (default `:phoenix_replay`)
  """

  @options [:on_mount, :authorize, :frame_layout, :live_socket_path, :as]

  @doc "Defines the dashboard routes under `path`."
  defmacro phoenix_replay(path, opts \\ []) do
    quote bind_quoted: [path: path, opts: opts] do
      {dashboard_session, frame_session, dashboard_opts, frame_opts} =
        PhoenixReplay.Router.__live_sessions__(Phoenix.Router.scoped_path(__MODULE__, path), opts)

      scope path, alias: false, as: false do
        import Phoenix.LiveView.Router, only: [live: 3, live_session: 3]

        get "/assets/:asset", PhoenixReplay.Web.Assets, []
        get "/:id/video/:token", PhoenixReplay.Web.Export.Download, []

        live_session dashboard_session, dashboard_opts do
          live "/", PhoenixReplay.Web.Live.Index, :index
          live "/:id", PhoenixReplay.Web.Live.Show, :show
        end

        live_session frame_session, frame_opts do
          live "/:id/frame", PhoenixReplay.Web.Live.Frame, :frame
        end
      end
    end
  end

  @doc """
  Builds live session names and options for `phoenix_replay/2`.

  Called at router compile time with the dashboard's full path.
  """
  @spec __live_sessions__(String.t(), keyword()) :: {atom(), atom(), keyword(), keyword()}
  def __live_sessions__(base_path, opts) do
    Keyword.validate!(opts, @options)

    context = %{
      base_path: base_path,
      authorize: opts[:authorize],
      live_socket_path: Keyword.get(opts, :live_socket_path, "/live")
    }

    on_mount = [{PhoenixReplay.Web.Context, context} | List.wrap(opts[:on_mount])]
    name = Keyword.get(opts, :as, :phoenix_replay)

    {name, :"#{name}_frame",
     [on_mount: on_mount, root_layout: {PhoenixReplay.Web.Layouts, :dashboard}],
     [
       on_mount: on_mount,
       root_layout: Keyword.get(opts, :frame_layout, {PhoenixReplay.Web.Layouts, :frame})
     ]}
  end
end
