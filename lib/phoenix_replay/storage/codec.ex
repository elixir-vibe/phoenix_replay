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
  Decodes a binary produced by `encode/1` into a `struct` of the given module.

  Returns `{:error, :undecodable}` for corrupt data, unknown atoms, or a term
  of a different shape.
  """
  @spec decode(binary(), module()) :: {:ok, struct()} | {:error, :undecodable}
  def decode(binary, struct) when is_binary(binary) and is_atom(struct) do
    case :erlang.binary_to_term(binary, [:safe]) do
      %^struct{} = term -> {:ok, term}
      _other -> {:error, :undecodable}
    end
  rescue
    ArgumentError -> {:error, :undecodable}
  end
end
