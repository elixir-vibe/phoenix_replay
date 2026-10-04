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
    5. Add `PhoenixReplay.Plug` to the `:browser` pipeline, which keeps the
       request context `:context` asks for; it does nothing until then
    6. Add `:user_agent` to the `:connect_info` of the endpoint's LiveView
       socket, so recordings name the browser
    7. Send the browser's viewport and tab from `assets/js/app.js` (or
       `app.ts`) with PhoenixReplay's client module, when its `LiveSocket`
       params are the ones Phoenix generates

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
      |> add_user_agent()
      |> send_client_context()
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
              igniter
              |> add_routes(router, app)
              |> add_context_plug(router)

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

    # A no-op until :context is configured, so turning it on is config only.
    defp add_context_plug(igniter, router) do
      {igniter, _source, zipper} = Igniter.Project.Module.find_module!(igniter, router)

      if Sourceror.Zipper.find(zipper, &match?({:__aliases__, _, [:PhoenixReplay, :Plug]}, &1)) do
        igniter
      else
        Phoenix.append_to_pipeline(igniter, :browser, "plug PhoenixReplay.Plug", router: router)
      end
    end

    @transports [:websocket, :longpoll]

    defp add_user_agent(igniter) do
      case Phoenix.select_endpoint(igniter) do
        {igniter, nil} ->
          Igniter.add_notice(igniter, user_agent_notice())

        {igniter, endpoint} ->
          Igniter.Project.Module.find_and_update_module!(igniter, endpoint, fn zipper ->
            case Function.move_to_function_call(zipper, :socket, 3, &live_socket?/1) do
              {:ok, zipper} -> Function.update_nth_argument(zipper, 2, &connect_user_agent/1)
              :error -> {:warning, user_agent_notice()}
            end
          end)
      end
    end

    defp live_socket?(zipper), do: Function.argument_equals?(zipper, 0, "/live")

    # Only transports the socket already configures, so none is turned on.
    # Prepended: keyword entries such as session: must come last.
    defp connect_user_agent(zipper) do
      Enum.reduce_while(@transports, {:ok, zipper}, fn transport, {:ok, zipper} ->
        if Igniter.Code.Keyword.keyword_has_path?(zipper, [transport]) do
          case Igniter.Code.Keyword.put_in_keyword(
                 zipper,
                 [transport, :connect_info],
                 [:user_agent],
                 &Igniter.Code.List.prepend_new_to_list(&1, :user_agent)
               ) do
            {:ok, zipper} -> {:cont, {:ok, zipper}}
            _error -> {:halt, {:warning, user_agent_notice()}}
          end
        else
          {:cont, {:ok, zipper}}
        end
      end)
    end

    @live_socket_params ~r/params:\s*\{\s*_csrf_token:\s*csrfToken\s*\},?/
    @client_import ~s(import { replayParams, replayMetadata } from "phoenix_replay"\n)

    defp send_client_context(igniter) do
      case Enum.find(["assets/js/app.js", "assets/js/app.ts"], &Igniter.exists?(igniter, &1)) do
        nil ->
          Igniter.add_notice(igniter, client_notice())

        path ->
          Igniter.update_file(igniter, path, fn source ->
            content = Rewrite.Source.get(source, :content)

            cond do
              String.contains?(content, "replayParams") ->
                source

              Regex.match?(@live_socket_params, content) ->
                Rewrite.Source.update(source, :content, wire_client(content))

              true ->
                {:warning, client_notice()}
            end
          end)
      end
    end

    defp wire_client(content) do
      content
      |> String.replace(
        @live_socket_params,
        "params: () => ({_csrf_token: csrfToken, ...replayParams()}),\n  metadata: replayMetadata,",
        global: false
      )
      |> add_client_import()
    end

    # After the last import, so it lands among the others: the greedy match
    # runs from the start of the file to the last line starting an import,
    # then on to its module string, which ends the statement even when the
    # imported names span several lines.
    defp add_client_import(content) do
      case Regex.run(~r/\A[\s\S]*^import\b[\s\S]*?["'][^"'\n]+["'];?[^\S\n]*$/m, content) do
        [imports] ->
          imports <>
            "\n" <>
            String.trim_trailing(@client_import) <>
            String.replace_prefix(content, imports, "")

        nil ->
          @client_import <> content
      end
    end

    defp user_agent_notice do
      """
      To record which browser a session used, add :user_agent to the
      :connect_info of your endpoint's LiveView socket:

          socket "/live", Phoenix.LiveView.Socket,
            websocket: [connect_info: [:user_agent, session: @session_options]]
      """
    end

    defp client_notice do
      """
      To record the browser's viewport and follow users across LiveViews,
      pass PhoenixReplay's client context to your LiveSocket:

          import { replayParams, replayMetadata } from "phoenix_replay"

          const liveSocket = new LiveSocket("/live", Socket, {
            params: () => ({_csrf_token: csrfToken, ...replayParams()}),
            metadata: replayMetadata
          })
      """
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
