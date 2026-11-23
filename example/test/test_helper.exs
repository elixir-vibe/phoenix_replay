Ecto.Adapters.SQL.Sandbox.mode(Example.Repo, :manual)

Application.put_env(:phoenix_test, :base_url, ExampleWeb.Endpoint.url())

ExUnit.start()
