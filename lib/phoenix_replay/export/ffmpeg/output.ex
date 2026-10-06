defmodule PhoenixReplay.Export.FFmpeg.Output do
  @moduledoc """
  Where MuonTrap writes `ffmpeg`'s output: each chunk is sent to the
  process following it, tagged with `ref`.
  """

  @type t :: %__MODULE__{to: pid(), ref: reference()}

  @enforce_keys [:to, :ref]
  defstruct [:to, :ref]

  defimpl Collectable do
    def into(output) do
      collect = fn
        output, {:cont, chunk} ->
          send(output.to, {output.ref, chunk})
          output

        output, :done ->
          output

        _output, :halt ->
          :ok
      end

      {output, collect}
    end
  end
end
