defmodule PhoenixReplay.Web.Params do
  @moduledoc """
  Reads values from URL and event params.
  """

  @doc """
  Parses a non-negative integer parameter, falling back to `default`.

  Accepts strings from `phx-value-*` attributes and integers from hook payloads.
  """
  @spec integer(term(), default) :: non_neg_integer() | default when default: term()
  def integer(value, _default) when is_integer(value) and value >= 0, do: value

  def integer(value, default) when is_binary(value) do
    case Integer.parse(value) do
      {integer, ""} when integer >= 0 -> integer
      _invalid -> default
    end
  end

  def integer(_value, default), do: default
end
