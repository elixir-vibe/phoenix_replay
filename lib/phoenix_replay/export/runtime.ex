defmodule PhoenixReplay.Export.Runtime do
  @moduledoc """
  Starts what exports need with the first export, under this supervisor:
  `PhoenixReplay.Export.Endpoint` and a connection to Playwright, so an
  application that never exports runs neither.
  """

  use DynamicSupervisor

  alias PhoenixReplay.Config
  alias PhoenixReplay.Export.Endpoint

  @playwright PhoenixReplay.Export.Playwright

  @typedoc "Where the browser loads the stage from, and the Playwright connection."
  @type t :: %{url: String.t(), connection: GenServer.name()}

  @doc false
  @spec start_link(keyword()) :: Supervisor.on_start()
  def start_link(_opts), do: DynamicSupervisor.start_link(__MODULE__, nil, name: __MODULE__)

  @impl true
  def init(nil), do: DynamicSupervisor.init(strategy: :one_for_one)

  @doc "Starts the endpoint and Playwright unless they run, and tells where they are."
  @spec ensure(Config.export()) :: {:ok, t()} | {:error, term()}
  def ensure(export) do
    playwright =
      Keyword.merge([name: @playwright, timeout: export.timeout], export.playwright)

    with :ok <-
           start(%{
             id: Endpoint,
             start: {Endpoint, :start_link, [Endpoint.settings()]},
             type: :supervisor
           }),
         :ok <-
           start(Supervisor.child_spec({PlaywrightEx.Supervisor, playwright}, id: @playwright)),
         {:ok, {_ip, port}} <- Endpoint.server_info(:http) do
      {:ok,
       %{
         url: "http://127.0.0.1:#{port}",
         connection: PlaywrightEx.Supervisor.connection_name(@playwright)
       }}
    end
  end

  defp start(spec) do
    case DynamicSupervisor.start_child(__MODULE__, spec) do
      {:ok, _pid} -> :ok
      {:error, {:already_started, _pid}} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end
end
