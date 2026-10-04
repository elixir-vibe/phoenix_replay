{:ok, _} = PhoenixReplay.Test.Endpoint.start_link()
ExUnit.start()

# Dashboard TypeScript tests from priv/ts run as ExUnit tests: pure modules in
# QuickBEAM, DOM helpers and LiveView hooks in a browser against the real
# LiveView client.
Volt.Test.ExUnit.install(exclude: ["client/**", "dom/**", "hooks/**", "test/**"])

Volt.Test.ExUnit.install(
  include: ["client/**/*.test.ts", "dom/**/*.test.ts", "hooks/**/*.test.ts"],
  browser: true
)
