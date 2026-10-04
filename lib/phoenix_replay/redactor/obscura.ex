if Code.ensure_loaded?(Obscura) do
  defmodule PhoenixReplay.Redactor.Obscura do
    @moduledoc """
    Finds personal data with [Obscura](https://hexdocs.pm/obscura) and
    replaces it with a placeholder such as `"[EMAIL]"`.

    Add the optional dependency and configure the redactor:

        def deps do
          [{:obscura, "~> 0.2"}]
        end

        config :phoenix_replay, redact: {PhoenixReplay.Redactor.Obscura, []}

    Obscura's deterministic `:fast` profile recognizes emails, phone
    numbers, card numbers, US social security numbers, IBANs and IP
    addresses. It takes roughly 0.1 to 0.3 ms per string, which is why it
    runs when a recording is saved rather than while your LiveViews run.

    ## Options

      * `:entities` — the entities to find. Defaults to `[:email, :phone,
        :credit_card, :us_ssn, :iban, :ip_address]`. `:url` and `:domain`
        are left out because they also match module and file names such as
        `"phoenix.html"`.

    Other options are passed to `Obscura.redact/2`, such as `:operators`
    to mask rather than replace. Obscura's model-backed profiles also find
    names and places, but take far longer and need local model assets; see
    its documentation before choosing one.
    """

    @behaviour PhoenixReplay.Redactor

    @entities [:email, :phone, :credit_card, :us_ssn, :iban, :ip_address]

    @impl true
    def redact(text, opts) do
      opts = opts |> Keyword.put_new(:entities, @entities) |> Keyword.put_new(:profile, :fast)

      case Obscura.redact(text, opts) do
        {:ok, %{text: redacted}} -> {:ok, redacted}
        {:error, reason} -> {:error, reason}
      end
    end
  end
end
