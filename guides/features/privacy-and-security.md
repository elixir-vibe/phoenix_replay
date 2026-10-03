# Privacy and Security

Recordings hold the assigns your users saw and the params they sent. Treat them like application data.

## Protect the dashboard

Mount the dashboard behind authentication, in a scope whose pipeline requires an admin, and pass your authentication hooks to `:on_mount`:

```elixir
scope "/admin" do
  pipe_through [:browser, :require_admin]
  phoenix_replay "/replay", on_mount: [{MyAppWeb.UserAuth, :ensure_admin}]
end
```

For rules per recording or action, add a `PhoenixReplay.Authorization` module; see [Dashboard](dashboard.md#authorization). Without one, everyone who reaches the dashboard can list, view and delete every recording.

## Sanitizing

Everything recorded passes through a `PhoenixReplay.Sanitizer` before it is stored: assigns with `sanitize_assigns/1`, and event params, URL params and the session with `sanitize_params/1`.

`PhoenixReplay.Sanitizer.Default`:

- replaces the values of keys containing `password`, `token`, `secret`, `api_key`, `apikey`, `private_key` or `credential`, in any case, with `"[FILTERED]"`; keys are kept so templates still render,
- recurses into maps, lists, tuples and structs, including Ecto schemas,
- compacts `Ecto.Changeset` and `Phoenix.HTML.Form` runtime metadata,
- drops LiveView internals that cannot be replayed.

## Custom sanitizers

Implement the behaviour and delegate to the default for what you keep:

```elixir
defmodule MyApp.ReplaySanitizer do
  @behaviour PhoenixReplay.Sanitizer

  @impl true
  def sanitize_assigns(assigns) do
    assigns
    |> Map.drop([:current_user, :billing_address])
    |> PhoenixReplay.Sanitizer.Default.sanitize_assigns()
  end

  @impl true
  defdelegate sanitize_params(params), to: PhoenixReplay.Sanitizer.Default
end
```

```elixir
config :phoenix_replay, sanitizer: MyApp.ReplaySanitizer
```

A sanitizer can also be set per live session with `on_mount: [{PhoenixReplay.Recorder, sanitizer: MyApp.CheckoutSanitizer}]`. Keep sanitizers free of exceptions: they run inside your LiveViews.

## Collected text

[Telemetry and log collection](telemetry-and-logs.md) records free text: SQL, log messages and exit reasons. Their metadata goes through `sanitize_params/1`, but text has no keys to filter, so mask sensitive values with `:redact` patterns:

```elixir
config :phoenix_replay, redact: [~r/\b\d{13,19}\b/, ~r/[\w.+-]+@[\w-]+\.[\w.]+/]
```

Matches are replaced with `"[REDACTED]"` by `PhoenixReplay.Sanitizer.redact/2`. Ecto query parameters and URL query strings are left out unless you enable them.

## What is never recorded

- `handle_info/2` message contents; only the message tag is kept,
- the contents of streams and uploads,
- anything that happens only in the browser.

## Retention

Keep recordings only as long as you need them, with `:retention` limits; see [Storage](storage.md#retention).
