defmodule PhoenixReplay.RedactorTest do
  use ExUnit.Case, async: true

  alias PhoenixReplay.Recording.Event
  alias PhoenixReplay.Redactor
  alias PhoenixReplay.Redactor.Patterns
  alias PhoenixReplay.Test.Fixtures

  defmodule Failing do
    @moduledoc false
    @behaviour PhoenixReplay.Redactor

    @impl true
    def redact("fail", _opts), do: {:error, :boom}
    def redact(text, _opts), do: {:ok, text}
  end

  @cards {Patterns, patterns: [~r/\d{4}-\d{4}/]}

  defmodule Card do
    @moduledoc false
    defstruct [:number, :note]
  end

  test "redacts strings inside maps, lists, tuples and structs, keeping keys and types" do
    date = ~D[2026-01-01]

    term = %{
      "1234-5678" => [%Card{number: "1234-5678", note: {"call 1234-5678", 7}}],
      date: date,
      count: 3,
      improper: [1 | "1234-5678"]
    }

    assert Redactor.redact_term(term, @cards) ==
             {:ok,
              %{
                "1234-5678" => [%Card{number: "[REDACTED]", note: {"call [REDACTED]", 7}}],
                date: date,
                count: 3,
                improper: [1 | "1234-5678"]
              }}
  end

  test "stops at the first failure" do
    assert Redactor.redact_term(%{a: ["ok", "fail"]}, {Failing, []}) == {:error, :boom}
  end

  test "redacts a recording's URL, params, session and events, reporting progress" do
    recording = %{
      Fixtures.counter_recording(clicks: 1)
      | url: "http://x/1234-5678",
        params: %{"card" => "1234-5678"},
        session: %{"note" => "1234-5678"},
        client: %{
          viewport: %{width: 1234, height: 5678, dpr: 1},
          user_agent: "Agent 1234-5678",
          tab: "1234-5678",
          referer: "http://x/1234-5678"
        }
    }

    log = %Event{
      at: 9,
      type: :log,
      data: %{level: :info, message: "paid 1234-5678", metadata: %{}}
    }

    recording = %{recording | events: [log | recording.events]}
    test = self()

    assert {:ok, redacted} =
             Redactor.redact_recording(recording, @cards, &send(test, {:progress, &1, &2}))

    assert redacted.url == "http://x/[REDACTED]"
    assert redacted.params == %{"card" => "[REDACTED]"}
    assert redacted.session == %{"note" => "[REDACTED]"}

    assert redacted.client == %{
             viewport: %{width: 1234, height: 5678, dpr: 1},
             user_agent: "Agent [REDACTED]",
             tab: "1234-5678",
             referer: "http://x/[REDACTED]"
           }

    assert Enum.find(redacted.events, &(&1.type == :log)).data.message == "paid [REDACTED]"

    total = length(recording.events)
    for done <- 1..total, do: assert_received({:progress, ^done, ^total})
  end
end
