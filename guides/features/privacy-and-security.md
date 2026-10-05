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

- replaces the values of keys containing `password`, `token`, `secret`, `api_key`, `apikey`, `private_key`, `credential`, `card_number`, `credit_card` or `one_time`, in any case, or with `cvv`, `cvc`, `csc`, `ssn`, `pin` or `otp` as a word of their own (`card_cvv`, `pinCode`, but not `shipping`), with `"[FILTERED]"`; keys are kept so templates still render,
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

## Redacting values

A sanitizer runs inside your LiveViews on every event, so it filters by key, which is cheap. An email address typed into a form, a card number in a log message or a phone number in SQL carries no telling key. Finding those takes detection, so a `PhoenixReplay.Redactor` masks them when a session is saved, in a background task, where its cost never reaches your users.

Mask matches of your own patterns:

```elixir
config :phoenix_replay, redact: [~r/\b\d{13,19}\b/, ~r/[\w.+-]+@[\w-]+\.[\w.]+/]
```

Or detect personal data with [Obscura](https://hexdocs.pm/obscura), an optional dependency:

```elixir
def deps do
  [{:obscura, "~> 0.2"}]
end
```

```elixir
config :phoenix_replay, redact: {PhoenixReplay.Redactor.Obscura, []}
```

`PhoenixReplay.Redactor.Obscura` finds emails, phone numbers, card numbers, US social security numbers, IBANs and IP addresses, and replaces them with placeholders such as `"[EMAIL]"`. Choose others with `entities:`.

The redactor sees every string in a recording: its URL, params and session, assigns, event params, and collected SQL, logs and exit reasons. Struct types are kept, so templates still render; a template that parses a redacted value may render differently than it did live.

Sessions still running are redacted when the dashboard opens them, so they show the same values as once they are saved. The player shows the redaction's progress meanwhile. If a redactor fails, the session is not saved and the dashboard does not show it: nothing unredacted is stored or displayed. The buffer of running sessions holds sanitized but unredacted values in memory until they are saved.

Ecto query parameters and URL query strings are left out of collected events unless you enable them.

## Form controls and client state

When the client module's `replayRecorder` runs, what users type and choose in form controls is recorded by default, with or without `phx-change`, and so is state your code reports with `replayState`. Both pass through `sanitize_params/1` under the control's name or the reported key, like event params.

These are never read in the browser at all, so they never leave it:

- password inputs, including one a "show password" toggle turned into text,
- fields whose `autocomplete` names a card (`cc-number`, `cc-csc`…), a password (`current-password`, `new-password`) or a one-time code (`one-time-code`),
- hidden and file inputs, and buttons,
- anything inside an element with `data-phx-replay-ignore`.

Mark anything else private with that attribute, such as a free-text field that may hold health or financial details:

```heex
<div data-phx-replay-ignore>
  <.input field={@form[:notes]} type="textarea" />
</div>
```

Turn form controls off with `state: [inputs: false]`, or all client state with `state: false`.

## What is never recorded

- `handle_info/2` message contents; only the message tag is kept,
- the contents of streams and uploads,
- the controls listed above, and what happens in the browser that neither a form control nor `replayState` reports.

## Retention

Keep recordings only as long as you need them, with `:retention` limits; see [Storage](storage.md#retention).
