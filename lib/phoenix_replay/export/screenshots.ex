if Code.ensure_loaded?(PlaywrightEx) do
  defmodule PhoenixReplay.Export.Screenshots do
    @moduledoc """
    Screenshots each shot of a `PhoenixReplay.Export.Schedule` in Chromium.

    It opens `PhoenixReplay.Web.Export.Stage` in a browser context the size
    of the schedule's canvas, at its device pixel ratio, waits until the
    stage's frame is ready, then has the stage show each shot's moment and
    saves a PNG of it. The stage seeks its frame itself. The browser is
    closed whatever happens, and a `{PhoenixReplay.Export, :cancel}` message
    stops it between screenshots.
    """

    alias PhoenixReplay.Export.{Encoder, Options, Runtime, Schedule}
    alias PlaywrightEx.{Browser, BrowserContext, Frame, Page}

    # Resolves once the stage's hook has mounted and its frame is ready.
    @ready """
    () => new Promise((resolve) => {
      const check = () =>
        window.phoenixReplayStage
          ? window.phoenixReplayStage.ready().then(() => resolve(true))
          : setTimeout(check, 20)
      check()
    })
    """

    @show "(shot) => window.phoenixReplayStage.show(shot)"

    @doc """
    Captures the shots of a recording's schedule into `dir`, reporting
    progress from 0 to 1.
    """
    @spec run(
            Runtime.t(),
            PhoenixReplay.Recording.id(),
            Schedule.t(),
            Path.t(),
            map(),
            Options.t(),
            (float() -> any())
          ) :: {:ok, Encoder.shots()} | {:error, term()}
    def run(runtime, recording_id, schedule, dir, export, options, progress) do
      opts = [connection: runtime.connection, timeout: export.timeout]

      with {:ok, browser} <- PlaywrightEx.launch_browser(:chromium, opts) do
        try do
          with {:ok, page} <- open(browser, schedule, opts),
               {:ok, _response} <-
                 Frame.goto(
                   page.main_frame.guid,
                   [url: Runtime.stage_url(runtime, recording_id, options)] ++ opts
                 ),
               {:ok, true} <-
                 Frame.evaluate(
                   page.main_frame.guid,
                   [expression: @ready, is_function: true] ++ opts
                 ) do
            shoot(schedule, page, dir, opts, progress)
          end
        after
          Browser.close(browser.guid, opts)
        end
      end
      |> browser_error()
    end

    defp open(browser, schedule, opts) do
      context_opts = [viewport: schedule.canvas, device_scale_factor: schedule.dpr / 1] ++ opts

      with {:ok, context} <- Browser.new_context(browser.guid, context_opts),
           do: BrowserContext.new_page(context.guid, opts)
    end

    defp shoot(schedule, page, dir, opts, progress) do
      count = length(schedule.shots)

      schedule.shots
      |> Enum.with_index()
      |> Enum.reduce_while({:ok, []}, fn {shot, number}, {:ok, shots} ->
        case if(cancelled?(), do: {:error, :cancelled}, else: screenshot(page, shot, opts)) do
          {:ok, png} ->
            path = Path.join(dir, "#{number}.png")
            File.write!(path, png)
            progress.((number + 1) / count)
            {:cont, {:ok, [{path, shot.frames} | shots]}}

          {:error, reason} ->
            {:halt, {:error, reason}}
        end
      end)
      |> case do
        {:ok, shots} -> {:ok, Enum.reverse(shots)}
        error -> error
      end
    end

    # The server asks a running export to stop between screenshots.
    defp cancelled? do
      receive do
        {PhoenixReplay.Export, :cancel} -> true
      after
        0 -> false
      end
    end

    defp screenshot(page, shot, opts) do
      arg = Map.take(shot, [:index, :at]) |> Map.merge(shot.viewport)

      with {:ok, _shown} <-
             Frame.evaluate(
               page.main_frame.guid,
               [expression: @show, is_function: true, arg: arg] ++ opts
             ),
           {:ok, base64} <- Page.screenshot(page.guid, opts),
           do: {:ok, Base.decode64!(base64)}
    end

    defp browser_error({:error, {:browser, _message}} = error), do: error
    defp browser_error({:error, :cancelled} = error), do: error
    defp browser_error({:error, %{message: message}}), do: {:error, {:browser, message}}

    defp browser_error({:error, {%{message: message}, _details}}),
      do: {:error, {:browser, message}}

    defp browser_error(result), do: result
  end
end
