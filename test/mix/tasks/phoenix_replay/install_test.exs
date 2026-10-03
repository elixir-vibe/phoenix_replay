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
end
