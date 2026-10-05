if Code.ensure_loaded?(PlaywrightEx) do
  defmodule PhoenixReplay.Export.Capture do
    @moduledoc """
    Screenshots each shot of a `PhoenixReplay.Export.Schedule` in Chromium.

    It opens `PhoenixReplay.Export.Stage` in a browser context the size of
    the schedule's canvas, at its device pixel ratio, waits for the frame
    to connect, then for each shot seeks the frame when the event changes,
    lets the stage show the moment, and saves a PNG. The browser is closed
    whatever happens.
    """

    alias PhoenixReplay.Export.{Access, Encoder, Runtime, Schedule}
    alias PhoenixReplay.Web.Player.Channel
    alias PlaywrightEx.{Browser, BrowserContext, Frame, Page}

    # Resolves once the stage's hook has mounted.
    @ready """
    () => new Promise((resolve) => {
      const check = () => (window.phoenixReplayStage ? resolve(true) : setTimeout(check, 20))
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
            PhoenixReplay.Config.export(),
            (float() -> any())
          ) :: {:ok, Encoder.shots()} | {:error, term()}
    def run(runtime, recording_id, schedule, dir, export, progress) do
      channel = Channel.new()
      :ok = Channel.subscribe(channel)
      opts = [connection: runtime.connection, timeout: export.timeout]

      with {:ok, browser} <- PlaywrightEx.launch_browser(:chromium, opts) do
        try do
          with {:ok, page} <- open(browser, schedule, opts),
               {:ok, _response} <-
                 Frame.goto(
                   page.main_frame.guid,
                   [url: stage_url(runtime, recording_id, channel)] ++ opts
                 ),
               :ok <- await_frame(channel, export.timeout),
               {:ok, true} <-
                 Frame.evaluate(
                   page.main_frame.guid,
                   [expression: @ready, is_function: true] ++ opts
                 ) do
            shoot(schedule, page, channel, dir, opts, progress)
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

    defp stage_url(runtime, recording_id, channel) do
      token = Access.sign(recording_id)
      "#{runtime.url}/_phoenix_replay/stage/#{token}?" <> URI.encode_query(channel: channel)
    end

    # The frame announces itself on the channel once its LiveView connects.
    defp await_frame(channel, timeout) do
      receive do
        {Channel, :frame_ready} -> :ok
      after
        timeout -> {:error, {:browser, "the replay frame did not connect for #{channel}"}}
      end
    end

    defp shoot(schedule, page, channel, dir, opts, progress) do
      count = length(schedule.shots)

      schedule.shots
      |> Enum.with_index()
      |> Enum.reduce_while({:ok, [], nil}, fn {shot, number}, {:ok, shots, shown} ->
        if shot.index != shown, do: Channel.seek(channel, shot.index)

        case screenshot(page, shot, opts) do
          {:ok, png} ->
            path = Path.join(dir, "#{number}.png")
            File.write!(path, png)
            progress.((number + 1) / count)
            {:cont, {:ok, [{path, shot.frames} | shots], shot.index}}

          {:error, reason} ->
            {:halt, {:error, reason}}
        end
      end)
      |> case do
        {:ok, shots, _shown} -> {:ok, Enum.reverse(shots)}
        error -> error
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
    defp browser_error({:error, %{message: message}}), do: {:error, {:browser, message}}

    defp browser_error({:error, {%{message: message}, _details}}),
      do: {:error, {:browser, message}}

    defp browser_error(result), do: result
  end
end
