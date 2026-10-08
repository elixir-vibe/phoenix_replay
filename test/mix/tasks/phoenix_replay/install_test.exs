defmodule Mix.Tasks.PhoenixReplay.InstallTest do
  use ExUnit.Case, async: true

  import Igniter.Test

  # The router as Phoenix 1.8 generates it, trimmed to what the installer reads.
  @router """
  defmodule TestWeb.Router do
    use Phoenix.Router
    import Phoenix.LiveView.Router

    pipeline :browser do
      plug :accepts, ["html"]
      plug :fetch_session
    end

    scope "/" do
      pipe_through :browser
    end
  end
  """

  @formatter """
  [
    import_deps: [:phoenix],
    inputs: ["*.{ex,exs}", "{config,lib,test}/**/*.{ex,exs}"]
  ]
  """

  defp install(files \\ %{}) do
    [
      files:
        Map.merge(%{"lib/test_web/router.ex" => @router, ".formatter.exs" => @formatter}, files)
    ]
    |> test_project()
    |> Igniter.compose_task("phoenix_replay.install", [])
  end

  defp content(igniter, path) do
    igniter.rewrite |> Rewrite.source!(path) |> Rewrite.Source.get(:content)
  end

  test "mounts the dashboard behind dev routes" do
    router = install() |> content("lib/test_web/router.ex")

    assert router =~ "if Application.compile_env(:test, :dev_routes) do"
    assert router =~ "import PhoenixReplay.Router"
    assert router =~ ~s(scope "/dev" do)
    # Without phoenix_replay installed as a dependency here, the formatter
    # cannot read its locals_without_parens, so either form is accepted.
    assert router =~ ~r{phoenix_replay[ (]"/replay"}
  end

  test "adds the context plug to the :browser pipeline once" do
    router =
      install()
      |> apply_igniter!()
      |> Igniter.compose_task("phoenix_replay.install", [])
      |> content("lib/test_web/router.ex")

    assert [_one] = Regex.scan(~r/plug PhoenixReplay\.Plug/, router)
  end

  test "warns instead of mounting without a :browser pipeline" do
    router = "defmodule TestWeb.Router do\n  use Phoenix.Router\nend\n"
    igniter = install(%{"lib/test_web/router.ex" => router})

    assert_unchanged(igniter, "lib/test_web/router.ex")
    assert_has_warning(igniter, &(&1 =~ "has no :browser pipeline"))
  end

  test "turns recording off in tests and enables dev routes" do
    igniter = install()

    assert content(igniter, "config/test.exs") =~ "config :phoenix_replay, sample_rate: 0.0"
    assert content(igniter, "config/dev.exs") =~ "dev_routes: true"
  end

  test "imports the formatter config and ignores recordings" do
    igniter = install(%{".gitignore" => "/_build/\n"})

    assert content(igniter, ".formatter.exs") =~ "import_deps: [:phoenix_replay, :phoenix]"
    assert content(igniter, ".gitignore") =~ "/priv/replay_recordings/"
  end

  test "explains how to record a live session" do
    assert_has_notice(install(), &(&1 =~ "on_mount: [PhoenixReplay.Recorder]"))
  end

  test "is idempotent" do
    installed = install(%{".gitignore" => "/_build/\n"}) |> apply_igniter!()

    installed
    |> Igniter.compose_task("phoenix_replay.install", [])
    |> assert_unchanged()
  end

  @endpoint """
  defmodule TestWeb.Endpoint do
    use Phoenix.Endpoint, otp_app: :test

    socket "/live", Phoenix.LiveView.Socket,
      websocket: [connect_info: [session: @session_options]],
      longpoll: [connect_info: [session: @session_options]]
  end
  """

  # The LiveSocket setup as Phoenix 1.8 generates it.
  @app_js """
  import "phoenix_html"
  import {Socket} from "phoenix"
  import {LiveSocket} from "phoenix_live_view"

  const csrfToken = document.querySelector("meta[name='csrf-token']").getAttribute("content")
  const liveSocket = new LiveSocket("/live", Socket, {
    longPollFallbackMs: 2500,
    params: {_csrf_token: csrfToken},
    hooks: {},
  })
  """

  test "records the user agent on transports the socket already has" do
    endpoint =
      install(%{"lib/test_web/endpoint.ex" => @endpoint}) |> content("lib/test_web/endpoint.ex")

    assert endpoint =~ "websocket: [connect_info: [:user_agent, session: @session_options]]"
    assert endpoint =~ "longpoll: [connect_info: [:user_agent, session: @session_options]]"

    websocket_only = """
    defmodule TestWeb.Endpoint do
      use Phoenix.Endpoint, otp_app: :test

      socket "/live", Phoenix.LiveView.Socket, websocket: [connect_info: [session: @session_options]]
    end
    """

    endpoint =
      install(%{"lib/test_web/endpoint.ex" => websocket_only})
      |> content("lib/test_web/endpoint.ex")

    refute endpoint =~ "longpoll"
  end

  test "sends the client context from the generated LiveSocket setup" do
    app = install(%{"assets/js/app.js" => @app_js}) |> content("assets/js/app.js")

    assert app =~
             ~s(import {LiveSocket} from "phoenix_live_view"\nimport { replayParams, replayMetadata } from "phoenix_replay")

    assert app =~ "params: () => ({_csrf_token: csrfToken, ...replayParams()}),"
    assert app =~ "metadata: replayMetadata,"
    refute app =~ "params: {_csrf_token: csrfToken}"
  end

  test "records the pointer when the LiveSocket setup connects" do
    app = @app_js <> "\nliveSocket.connect()\nwindow.liveSocket = liveSocket\n"
    content = install(%{"assets/js/app.js" => app}) |> content("assets/js/app.js")

    assert content =~
             ~s(import { replayParams, replayMetadata, replayRecorder } from "phoenix_replay")

    assert content =~ "liveSocket.connect()\nreplayRecorder(liveSocket)\nwindow.liveSocket"
  end

  test "adds the import after a last import that spans several lines" do
    app =
      String.replace(
        @app_js,
        ~s(import {LiveSocket} from "phoenix_live_view"\n),
        ~s(import {LiveSocket} from "phoenix_live_view"\nimport {\n  hooks as colocatedHooks,\n} from "phoenix-colocated/test"\n)
      )

    content = install(%{"assets/js/app.js" => app}) |> content("assets/js/app.js")

    assert content =~
             ~s(} from "phoenix-colocated/test"\nimport { replayParams, replayMetadata } from "phoenix_replay"\n)
  end

  test "leaves custom LiveSocket setups alone and explains instead" do
    custom = String.replace(@app_js, "params: {_csrf_token: csrfToken},", "params: myParams,")
    igniter = install(%{"assets/js/app.js" => custom})

    assert_unchanged(igniter, "assets/js/app.js")
    assert_has_warning(igniter, &(&1 =~ "replayParams"))
  end

  test "does not wire the client context twice" do
    igniter =
      [files: %{"assets/js/app.js" => @app_js}]
      |> test_project()
      |> Igniter.compose_task("phoenix_replay.install", [])
      |> apply_igniter!()
      |> Igniter.compose_task("phoenix_replay.install", [])

    assert_unchanged(igniter, "assets/js/app.js")
  end
end
