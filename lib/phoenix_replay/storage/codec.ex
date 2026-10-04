defmodule PhoenixReplay.Storage.Codec do
  @moduledoc """
  Binary encoding shared by the storage backends.

  Terms are stored in compressed Erlang External Term Format, which keeps
  structs, atoms and tuples intact so recordings re-render exactly.
  Decoding uses `:safe` mode, so a recording that references atoms this node
  has never seen fails to decode instead of growing the atom table.
  """

  @frame_marker "PRF1"

  @doc "Encodes a term."
  @spec encode(term()) :: binary()
  def encode(term), do: :erlang.term_to_binary(term, compressed: 6)

  @doc """
  Decodes a binary produced by `encode/1` into a `struct` of the given
  module, or into a list when `shape` is `:list`.

  Structs are rebuilt with `struct/2`, so data written before a field was
  added gets the field's default.

  Recordings hold module names, such as the structs in assigns, and safe
  decoding refuses atoms the VM has not created yet. In development, where
  modules load on first use, a recording can name a module that exists but
  has not been loaded since the node started. The first time a binary does
  not decode, modules available on the code path but not yet loaded are
  loaded, which creates only the atoms of modules that really exist, and
  decoding is retried.

  Returns `{:error, :undecodable}` for corrupt data, atoms of no known
  module, or a term of a different shape.
  """
  @spec decode(binary(), module() | :list) :: {:ok, struct() | list()} | {:error, :undecodable}
  def decode(binary, shape) when is_binary(binary) and is_atom(shape) do
    with {:error, :undecodable} <- safe_decode(binary, shape),
         true <- load_available_modules() do
      safe_decode(binary, shape)
    else
      false -> {:error, :undecodable}
      decoded -> decoded
    end
  end

  defp safe_decode(binary, shape) do
    binary |> :erlang.binary_to_term([:safe]) |> shape(shape)
  rescue
    ArgumentError -> {:error, :undecodable}
  end

  # Loads at most once per node; false when that already happened.
  defp load_available_modules do
    if :persistent_term.get({__MODULE__, :modules_loaded}, false) do
      false
    else
      for {name, _file, false} <- :code.all_available(),
          do: :code.ensure_loaded(List.to_atom(name))

      :persistent_term.put({__MODULE__, :modules_loaded}, true)
      true
    end
  end

  @doc """
  Encodes a term as a frame that can be appended to a file.

  A frame is a marker, the payload's byte size and CRC32, then the payload
  encoded by `encode/1`. `decode_frames/1` stops at the first frame that is
  cut short or fails its checksum, so a write torn by a crash loses only
  itself.
  """
  @spec frame(term()) :: iodata()
  def frame(term) do
    payload = encode(term)
    [@frame_marker, <<byte_size(payload)::32, :erlang.crc32(payload)::32>>, payload]
  end

  @doc """
  Decodes the frames at the start of `binary`, in order, stopping at the
  first incomplete or corrupt one.
  """
  @spec decode_frames(binary()) :: [term()]
  def decode_frames(binary) when is_binary(binary), do: decode_frames(binary, [])

  defp decode_frames(
         <<@frame_marker, size::32, crc::32, payload::binary-size(size), rest::binary>>,
         acc
       ) do
    with true <- :erlang.crc32(payload) == crc,
         {:ok, term} <- safe_decode(payload) do
      decode_frames(rest, [term | acc])
    else
      _corrupt -> Enum.reverse(acc)
    end
  end

  defp decode_frames(_rest, acc), do: Enum.reverse(acc)

  defp safe_decode(payload) do
    {:ok, :erlang.binary_to_term(payload, [:safe])}
  rescue
    ArgumentError -> :error
  end

  defp shape(term, :list) when is_list(term), do: {:ok, term}

  defp shape(%{__struct__: struct} = term, struct),
    do: {:ok, struct(struct, Map.from_struct(term))}

  defp shape(_term, _shape), do: {:error, :undecodable}
end
