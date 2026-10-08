defmodule PhoenixReplay.Export.Runtime do
  @moduledoc """
  Starts what exports need with the first export, under this supervisor:
  `PhoenixReplay.Web.Export.Endpoint` and a connection to Playwright, so
  an application that never exports runs neither.

  The endpoint listens on 127.0.0.1 and a free port, with a secret made
  when it starts and given to it as an argument rather than kept in the
  application environment. Tokens for the stage are signed with that
  secret, so they die with the endpoint; `stage_url/3` makes one for a
  recording, and `verify/2` reads it.
  """

  use DynamicSupervisor

  alias PhoenixReplay.Config
  alias PhoenixReplay.Export.Options

  # Only called once `PhoenixReplay.Export.available/1` found PlaywrightEx,
  # an optional dependency.
  @compile {:no_warn_undefined, PlaywrightEx.Supervisor}

  @endpoint PhoenixReplay.Web.Export.Endpoint
  @playwright PhoenixReplay.Export.Playwright
  @secret {__MODULE__, :secret}
  @salt "phoenix_replay export"
  # As long as an export may take.
  @max_age 6 * 60 * 60

  @typedoc "Where the browser loads the stage from, and the Playwright connection."
  @type t :: %{url: String.t(), connection: GenServer.name()}

  @doc "Starts the supervisor the endpoint and Playwright are started under on demand."
  @spec start_link(keyword()) :: Supervisor.on_start()
  def start_link(_opts), do: DynamicSupervisor.start_link(__MODULE__, nil, name: __MODULE__)

  @impl true
  def init(nil), do: DynamicSupervisor.init(strategy: :one_for_one)

  @doc "Starts the endpoint and Playwright unless they run, and tells where they are."
  @spec ensure(Config.export()) :: {:ok, t()} | {:error, term()}
  def ensure(export) do
    playwright = Keyword.merge([name: @playwright, timeout: export.timeout], export.playwright)

    with :ok <-
           start(%{id: @endpoint, start: {__MODULE__, :start_endpoint, []}, type: :supervisor}),
         :ok <-
           start(Supervisor.child_spec({PlaywrightEx.Supervisor, playwright}, id: @playwright)),
         # The adapter is whichever web server the app has, so it is
         # looked up when it runs.
         {:ok, {_ip, port}} <- apply(adapter(), :server_info, [@endpoint, :http]) do
      {:ok,
       %{
         url: "http://127.0.0.1:#{port}",
         connection: PlaywrightEx.Supervisor.connection_name(@playwright)
       }}
    end
  end

  @doc """
  Starts the endpoint with its configuration as arguments: a loopback
  address, a free port, and secrets made for this start. Children start
  one at a time, so only the start that starts it makes the secret.
  """
  @spec start_endpoint() :: Supervisor.on_start()
  def start_endpoint do
    case Process.whereis(@endpoint) do
      nil ->
        secret = secret(64)
        :persistent_term.put(@secret, secret)
        @endpoint.start_link(settings(secret))

      pid ->
        {:error, {:already_started, pid}}
    end
  end

  @doc """
  The address of the stage for a recording, with a token that opens it,
  and whether the export draws the pointer.
  """
  @spec stage_url(t(), PhoenixReplay.Recording.id(), Options.t()) :: String.t()
  def stage_url(runtime, recording_id, %Options{} = options) do
    token = Phoenix.Token.sign(:persistent_term.get(@secret), @salt, recording_id)
    query = URI.encode_query(pointer: options.pointer)
    "#{runtime.url}/_phoenix_replay/stage/#{token}?#{query}"
  end

  @doc "Reads a stage token with the endpoint that serves the stage."
  @spec verify(module(), String.t()) :: {:ok, PhoenixReplay.Recording.id()} | {:error, atom()}
  def verify(endpoint, token), do: Phoenix.Token.verify(endpoint, @salt, token, max_age: @max_age)

  defp settings(secret) do
    [
      adapter: adapter(),
      http: [ip: {127, 0, 0, 1}, port: 0],
      url: [host: "127.0.0.1"],
      server: true,
      secret_key_base: secret,
      live_view: [signing_salt: secret(16)],
      pubsub_server: PhoenixReplay.PubSub,
      check_origin: false,
      render_errors: [formats: [html: PhoenixReplay.Web.Export.ErrorHTML], layout: false]
    ]
  end

  # Your app has Bandit or Cowboy; Phoenix serves with either.
  defp adapter do
    if Code.ensure_loaded?(Bandit.PhoenixAdapter),
      do: Bandit.PhoenixAdapter,
      else: Phoenix.Endpoint.Cowboy2Adapter
  end

  defp secret(bytes), do: bytes |> :crypto.strong_rand_bytes() |> Base.url_encode64()

  defp start(spec) do
    case DynamicSupervisor.start_child(__MODULE__, spec) do
      {:ok, _pid} -> :ok
      {:error, {:already_started, _pid}} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end
end
