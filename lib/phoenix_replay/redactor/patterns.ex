defmodule PhoenixReplay.Redactor.Patterns do
  @moduledoc """
  Replaces matches of regexes with `"[REDACTED]"`.

  This is the redactor behind a list of patterns in `:redact`:

      config :phoenix_replay,
        redact: [~r/\\b\\d{13,19}\\b/, ~r/[\\w.+-]+@[\\w-]+\\.[\\w.]+/]

  Patterns can be given as strings, which is convenient in releases. With
  no patterns, recordings are stored as the sanitizer left them.

  ## Options

    * `:patterns` — compiled regexes (required)
  """

  @behaviour PhoenixReplay.Redactor

  @redacted "[REDACTED]"

  @impl true
  def redact(text, opts) do
    {:ok, Enum.reduce(Keyword.fetch!(opts, :patterns), text, &Regex.replace(&1, &2, @redacted))}
  end
end
