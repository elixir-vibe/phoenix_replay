defmodule PhoenixReplay.Storage.Codec do
  @moduledoc """
  Binary encoding shared by the storage backends.

  Terms are stored in compressed Erlang External Term Format, which keeps
  structs, atoms and tuples intact so recordings re-render exactly.
  Decoding uses `:safe` mode, so a recording that references atoms this node
  has never seen fails to decode instead of growing the atom table.
  """

  @doc "Encodes a term."
  @spec encode(term()) :: binary()
  def encode(term), do: :erlang.term_to_binary(term, compressed: 6)

  @doc """
  Decodes a binary produced by `encode/1` into a `struct` of the given
  module, or into a list when `shape` is `:list`.

  Structs are rebuilt with `struct/2`, so data written before a field was
  added gets the field's default.

  Returns `{:error, :undecodable}` for corrupt data, unknown atoms, or a term
  of a different shape.
  """
  @spec decode(binary(), module() | :list) :: {:ok, struct() | list()} | {:error, :undecodable}
  def decode(binary, shape) when is_binary(binary) and is_atom(shape) do
    binary |> :erlang.binary_to_term([:safe]) |> shape(shape)
  rescue
    ArgumentError -> {:error, :undecodable}
  end

  defp shape(term, :list) when is_list(term), do: {:ok, term}

  defp shape(%{__struct__: struct} = term, struct),
    do: {:ok, struct(struct, Map.from_struct(term))}

  defp shape(_term, _shape), do: {:error, :undecodable}
end
