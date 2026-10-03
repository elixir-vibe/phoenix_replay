if Code.ensure_loaded?(Igniter) do
  defmodule Mix.Tasks.PhoenixReplay.Install do
    @shortdoc "Install PhoenixReplay in a Phoenix project"

    @moduledoc """
    #{@shortdoc}

    ## Example

        mix igniter.install phoenix_replay

    This installer will:

    1. Import `:phoenix_replay` in `.formatter.exs`
    2. Mount the dashboard at `/dev/replay` in your router, behind
       `Application.compile_env(app, :dev_routes)` like Phoenix's
       LiveDashboard, and enable `:dev_routes` in `config/dev.exs`
    3. Turn recording off in `config/test.exs` with `sample_rate: 0.0`, so
       your LiveView tests do not record sessions
    4. Ignore the default recordings directory in `.gitignore`

    Choosing which live sessions to record is up to you; the installer
    prints how to add `PhoenixReplay.Recorder` to them. Before using the
    dashboard outside development, mount it behind your own authentication.
    """

    use Igniter.Mix.Task

    alias Igniter.Code.Function
    alias Igniter.Libs.Phoenix
    alias Igniter.Project.Config, as: ProjectConfig
    alias Igniter.Project.Formatter, as: ProjectFormatter

    @recordings_dir "/priv/replay_recordings/"

    @impl Igniter.Mix.Task
    def info(_argv, _composing_task) do
      %Igniter.Mix.Task.Info{
        group: :phoenix_replay,
        example: "mix igniter.install phoenix_replay"
      }
    end

    @impl Igniter.Mix.Task
    def igniter(igniter) do
      app = Igniter.Project.Application.app_name(igniter)

      igniter
      |> ProjectFormatter.import_dep(:phoenix_replay)
      |> mount_dashboard(app)
      |> ProjectConfig.configure_new("dev.exs", app, [:dev_routes], true)
      |> ProjectConfig.configure_new("test.exs", :phoenix_replay, [:sample_rate], 0.0)
      |> ignore_recordings()
      |> Igniter.add_notice(notice())
    end

    defp mount_dashboard(igniter, app) do
      case Phoenix.select_router(igniter) do
        {igniter, nil} ->
          Igniter.add_warning(
            igniter,
            "No Phoenix router found. Add the dashboard manually:\n\n" <> routes(app)
          )

        {igniter, router} ->
          case Phoenix.has_pipeline(igniter, router, :browser) do
            {igniter, true} ->
              add_routes(igniter, router, app)

            {igniter, false} ->
              Igniter.add_warning(
                igniter,
                "#{inspect(router)} has no :browser pipeline. Add the dashboard manually:\n\n" <>
                  routes(app)
              )
          end
      end
    end

    defp add_routes(igniter, router, app) do
      Igniter.Project.Module.find_and_update_module!(igniter, router, fn zipper ->
        if mounted?(zipper),
          do: {:ok, zipper},
          else: {:ok, Igniter.Code.Common.add_code(zipper, routes(app))}
      end)
    end

    defp mounted?(zipper) do
      match?({:ok, _zipper}, Function.move_to_function_call(zipper, :phoenix_replay, [1, 2]))
    end

    defp routes(app) do
      """
      if Application.compile_env(#{inspect(app)}, :dev_routes) do
        import PhoenixReplay.Router

        scope "/dev" do
          pipe_through :browser

          phoenix_replay "/replay"
        end
      end
      """
    end

    defp ignore_recordings(igniter) do
      if Igniter.exists?(igniter, ".gitignore") do
        Igniter.update_file(igniter, ".gitignore", fn source ->
          content = Rewrite.Source.get(source, :content)

          if String.contains?(content, @recordings_dir) do
            source
          else
            addition =
              "\n# Session recordings from PhoenixReplay's file storage.\n#{@recordings_dir}\n"

            Rewrite.Source.update(
              source,
              :content,
              String.trim_trailing(content) <> "\n" <> addition
            )
          end
        end)
      else
        igniter
      end
    end

    defp notice do
      """
      PhoenixReplay is installed. To record a live session, add the recorder
      to its on_mount hooks:

          live_session :default, on_mount: [PhoenixReplay.Recorder] do
            live "/", HomeLive
          end

      Then use your app and open /dev/replay.

      The dashboard is mounted only when :dev_routes is enabled. To use it in
      production, mount it behind your own authentication instead:

          scope "/admin" do
            pipe_through [:browser, :require_admin]
            phoenix_replay "/replay"
          end

      Recording is off in config/test.exs. See
      https://hexdocs.pm/phoenix_replay/getting-started.html
      """
    end
  end
end
