{:ok, _} = PhoenixReplay.Test.Endpoint.start_link()
ExUnit.start()

# Dashboard TypeScript tests from priv/ts run as ExUnit tests: pure modules in
# QuickBEAM, LiveView hooks in a browser against the real LiveView client.
Volt.Test.ExUnit.install(exclude: ["hooks/**", "test/**"])
Volt.Test.ExUnit.install(include: ["hooks/**/*.test.ts"], browser: true)
