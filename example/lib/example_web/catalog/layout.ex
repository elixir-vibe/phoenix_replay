defmodule ExampleWeb.Catalog.Layout do
  @moduledoc """
  Root layout for the component catalogue: the app's JavaScript with
  PhoenixReplay's dashboard stylesheet, so components render as they do
  in the dashboard.
  """

  use ExampleWeb, :html

  def root(assigns) do
    ~H"""
    <!DOCTYPE html>
    <html lang="en" class="antialiased">
      <head>
        <meta charset="utf-8" />
        <meta name="viewport" content="width=device-width, initial-scale=1" />
        <meta name="csrf-token" content={get_csrf_token()} />
        <title>Components · PhoenixReplay</title>
        <link
          rel="stylesheet"
          href={"/replay/assets/" <> PhoenixReplay.Web.Assets.file_name(:css)}
        />
        <script
          defer
          type="module"
          src={Volt.static_path(ExampleWeb.Endpoint, "/assets/js/app.js")}
        >
        </script>
      </head>
      <body class="min-h-screen bg-canvas font-sans text-ink">
        {@inner_content}
      </body>
    </html>
    """
  end
end
