if Code.ensure_loaded?(MuonTrap) do
  defmodule PhoenixReplay.Export.FFmpeg do
    @moduledoc """
    Runs `ffmpeg` and follows it until it is done.

    [MuonTrap](https://hexdocs.pm/muontrap) runs it, so it never outlives
    the process that started it, even when the VM itself goes down, and
    stopping it is ending that process: MuonTrap terminates `ffmpeg`, and
    kills it if it does not exit.

    `ffmpeg` is expected to report its progress on stdout, with
    `-progress pipe:1`. While it does, it is working. When it says nothing
    for `timeout`, it is taken as stuck and stopped. The export server
    cancels a running export by sending `{PhoenixReplay.Export, :cancel}`,
    which stops it too.
    """

    require Logger

    alias __MODULE__.Output

    @typedoc "Called with how much of the video is encoded so far, in milliseconds."
    @type progress :: (non_neg_integer() -> any())

    @typedoc "Why `ffmpeg` did not finish: its exit status, or that it went quiet."
    @type error :: {:ffmpeg, pos_integer() | :timeout} | :cancelled

    # The last lines of output kept, to log when ffmpeg fails.
    @kept_lines 20

    # What `-progress` reports, a `key=value` line each, about ten times a
    # report: none of it explains a failure.
    @progress_keys ~w(frame fps bitrate total_size out_time_us out_time_ms out_time
                      dup_frames drop_frames speed progress)

    @doc """
    Runs the `ffmpeg` at `executable` with `args`, calling `progress` as
    it encodes. Returns once it exits, is cancelled, or goes quiet for
    `timeout` milliseconds.
    """
    @spec run(Path.t(), [String.t()], progress(), pos_integer()) :: :ok | {:error, error()}
    def run(executable, args, progress, timeout) do
      ref = make_ref()
      output = %Output{to: self(), ref: ref}

      task =
        Task.async(fn ->
          MuonTrap.cmd(executable, args, into: output, stderr_to_stdout: true)
        end)

      follow(%{task: task, ref: ref, progress: progress, timeout: timeout, rest: "", lines: []})
    end

    defp follow(%{task: %Task{ref: task_ref}, ref: ref} = run) do
      receive do
        {^ref, chunk} ->
          run |> read(chunk) |> follow()

        {^task_ref, {_output, 0}} ->
          Process.demonitor(task_ref, [:flush])
          :ok

        {^task_ref, {_output, status}} ->
          Process.demonitor(task_ref, [:flush])

          Logger.error([
            "PhoenixReplay: ffmpeg failed:\n" | Enum.intersperse(Enum.reverse(run.lines), "\n")
          ])

          {:error, {:ffmpeg, status}}

        {PhoenixReplay.Export, :cancel} ->
          stop(run)
          {:error, :cancelled}
      after
        run.timeout ->
          stop(run)
          {:error, {:ffmpeg, :timeout}}
      end
    end

    # Output arrives in chunks; whole lines are read, the rest waits for
    # the next chunk.
    defp read(run, chunk) do
      [rest | lines] = (run.rest <> chunk) |> String.split("\n") |> Enum.reverse()
      Enum.reduce(Enum.reverse(lines), %{run | rest: rest}, &line/2)
    end

    # Progress comes as `key=value` lines; the time encoded so far is
    # `out_time_us`, and the rest is dropped. Anything else is what ffmpeg
    # says about its work, kept in case it fails.
    defp line("out_time_us=" <> microseconds, run) do
      case Integer.parse(microseconds) do
        {done, ""} -> run.progress.(div(done, 1_000))
        _not_yet -> :ok
      end

      run
    end

    # Kept newest first.
    defp line(line, run) do
      if progress?(line),
        do: run,
        else: %{run | lines: [line | Enum.take(run.lines, @kept_lines - 1)]}
    end

    # A report's own keys, and the quantizer of each video stream, such as
    # `stream_0_0_q`.
    defp progress?(line) do
      case String.split(line, "=", parts: 2) do
        [key, _value] -> key in @progress_keys or Regex.match?(~r/\Astream_\d+_\d+_q\z/, key)
        [_line] -> false
      end
    end

    # Ending the task closes MuonTrap's port, and MuonTrap stops ffmpeg.
    defp stop(run), do: Task.shutdown(run.task, :brutal_kill)
  end
end
