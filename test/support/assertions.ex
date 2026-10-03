defmodule PhoenixReplay.Test.Assertions do
  @moduledoc "Assertions for asynchronous recording behaviour."

  import ExUnit.Assertions

  @doc "Retries `fun` until it returns `{:ok, value}` and returns `value`."
  @spec eventually((-> {:ok, value} | term()), pos_integer()) :: value when value: term()
  def eventually(fun, timeout \\ 5000) do
    deadline = System.monotonic_time(:millisecond) + timeout
    retry(fun, deadline)
  end

  defp retry(fun, deadline) do
    case fun.() do
      {:ok, value} ->
        value

      other ->
        if System.monotonic_time(:millisecond) > deadline do
          flunk("condition not met, last result: #{inspect(other)}")
        else
          Process.sleep(10)
          retry(fun, deadline)
        end
    end
  end
end
