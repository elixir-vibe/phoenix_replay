defmodule PhoenixReplay.Web.Layouts do
  @moduledoc """
  Root layouts for the dashboard and the default replay frame.

  Both load the host's Phoenix and LiveView clients followed by the dashboard
  bundle, all served by `PhoenixReplay.Web.Assets`. The dashboard also loads
  its own stylesheet; the frame loads the host's, so recorded views look the
  way users saw them.
  """

  use Phoenix.Component

  alias PhoenixReplay.Web.{Assets, Context}

  @type assets :: %{
          live_socket_path: String.t(),
          scripts: [String.t()],
          stylesheet: String.t()
        }

  @doc "Asset URLs for the dashboard layout."
  @spec dashboard_assets(Context.t()) :: assets()
  def dashboard_assets(context), do: assets(context, asset_path(context, :css))

  @doc "Asset URLs for the default frame layout, using the host endpoint's stylesheet."
  @spec frame_assets(Context.t(), module()) :: assets()
  def frame_assets(context, endpoint),
    do: assets(context, endpoint.static_path("/assets/css/app.css"))

  defp assets(context, stylesheet) do
    %{
      live_socket_path: context.live_socket_path,
      scripts: Enum.map([:phoenix, :phoenix_live_view, :js], &asset_path(context, &1)),
      stylesheet: stylesheet
    }
  end

  defp asset_path(context, kind), do: Context.path(context, ["assets", Assets.file_name(kind)])

  @doc "Root layout for the recording list and player."
  @spec dashboard(map()) :: Phoenix.LiveView.Rendered.t()
  def dashboard(assigns) do
    ~H"""
    <!DOCTYPE html>
    <html lang="en" class="h-full">
      <head>
        <meta charset="utf-8" />
        <meta name="viewport" content="width=device-width, initial-scale=1" />
        <meta name="csrf-token" content={Phoenix.Controller.get_csrf_token()} />
        <meta name="phoenix-replay-socket" content={@assets.live_socket_path} />
        <title>{assigns[:page_title] || "PhoenixReplay"}</title>
        <link rel="stylesheet" href={@assets.stylesheet} />
        <script :for={src <- @assets.scripts} defer src={src}>
        </script>
      </head>
      <body class="h-full bg-canvas font-sans text-ink antialiased">
        {@inner_content}
      </body>
    </html>
    """
  end

  @doc "Default root layout for the frame that re-renders recorded views."
  @spec frame(map()) :: Phoenix.LiveView.Rendered.t()
  def frame(assigns) do
    ~H"""
    <!DOCTYPE html>
    <html lang="en">
      <head>
        <meta charset="utf-8" />
        <meta name="viewport" content="width=device-width, initial-scale=1" />
        <meta name="csrf-token" content={Phoenix.Controller.get_csrf_token()} />
        <meta name="phoenix-replay-socket" content={@phoenix_replay_frame.assets.live_socket_path} />
        <link rel="stylesheet" href={@phoenix_replay_frame.assets.stylesheet} />
        <script :for={src <- @phoenix_replay_frame.assets.scripts} defer src={src}>
        </script>
        <style>
          body { pointer-events: none; user-select: none; }
        </style>
      </head>
      <body>
        {@inner_content}
      </body>
    </html>
    """
  end
end
