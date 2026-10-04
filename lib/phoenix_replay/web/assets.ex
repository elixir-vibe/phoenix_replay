defmodule PhoenixReplay.Web.Assets do
  @moduledoc """
  Serves the dashboard's JavaScript and CSS.

  Two kinds of files are served, all at versioned paths with immutable caching:

    * the dashboard bundle (`:js`, `:css`) built from `priv/ts` and
      `priv/css`, embedded at compile time and named by content hash, with
      the fonts the stylesheet refers to by relative URL
    * the host application's own Phoenix and LiveView clients
      (`:phoenix`, `:phoenix_live_view`), read from those dependencies and
      named by version, so the client always matches the server

  The files are public and contain no secrets, so responses opt out of
  `Plug.CSRFProtection`'s check against cross-origin script inclusion; the
  dashboard is usually mounted behind a pipeline with `:protect_from_forgery`.
  """

  @behaviour Plug

  import Plug.Conn

  @type kind :: :js | :css | :phoenix | :phoenix_live_view

  @bundle [
    js: {"dashboard.js", "text/javascript"},
    css: {"dashboard.css", "text/css"}
  ]

  # Read at compile time from the source tree and embedded, never at runtime.
  # credo:disable-for-next-line ExSlop.Check.Warning.PathExpandPriv
  @static Path.expand("../../../priv/static", __DIR__)

  @bundle_files (for {kind, {file, content_type}} <- @bundle, into: %{} do
                   path = Path.join(@static, file)
                   body = File.read!(path)
                   digest = :crypto.hash(:md5, body)
                   hash = digest |> Base.encode16(case: :lower) |> binary_part(0, 8)
                   name = Path.rootname(file) <> "-" <> hash <> Path.extname(file)
                   {kind, %{path: path, name: name, body: body, content_type: content_type}}
                 end)

  # Volt names the fonts by content hash already.
  @fonts (for path <- Path.wildcard(Path.join(@static, "*.woff2")) do
            %{
              path: path,
              name: Path.basename(path),
              body: File.read!(path),
              content_type: "font/woff2"
            }
          end)

  for %{path: path} <- Map.values(@bundle_files) ++ @fonts, do: @external_resource(path)

  @bundle_by_name Map.new(Map.values(@bundle_files) ++ @fonts, &{&1.name, &1})

  @clients [
    phoenix: "static/phoenix.min.js",
    phoenix_live_view: "static/phoenix_live_view.min.js"
  ]

  @doc "Returns the versioned file name for `kind`."
  @spec file_name(kind()) :: String.t()
  def file_name(kind) when is_map_key(@bundle_files, kind), do: @bundle_files[kind].name
  def file_name(app), do: "#{app}-#{Application.spec(app, :vsn)}.js"

  @impl true
  def init(opts), do: opts

  @impl true
  def call(%Plug.Conn{path_params: %{"asset" => name}} = conn, _opts) do
    case find(name) do
      {:ok, body, content_type} ->
        conn
        |> put_private(:plug_skip_csrf_protection, true)
        |> put_resp_content_type(content_type, charset(content_type))
        |> put_resp_header("cache-control", "public, max-age=31536000, immutable")
        |> send_resp(200, body)
        |> halt()

      :error ->
        conn |> send_resp(404, "Not Found") |> halt()
    end
  end

  defp charset("font/" <> _format), do: nil
  defp charset(_text), do: "utf-8"

  defp find(name) do
    case @bundle_by_name do
      %{^name => %{body: body, content_type: content_type}} -> {:ok, body, content_type}
      %{} -> find_client(name)
    end
  end

  defp find_client(name) do
    case Enum.find(@clients, fn {app, _file} -> file_name(app) == name end) do
      {app, file} -> {:ok, File.read!(Path.join(:code.priv_dir(app), file)), "text/javascript"}
      nil -> :error
    end
  end
end
