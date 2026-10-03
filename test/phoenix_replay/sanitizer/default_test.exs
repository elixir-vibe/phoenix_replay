defmodule PhoenixReplay.Sanitizer.DefaultTest do
  use ExUnit.Case, async: true

  alias PhoenixReplay.Sanitizer.Default

  defmodule Account do
    defstruct [:name, :api_key, :profile]
  end

  test "filters sensitive keys by substring, case-insensitively" do
    assert Default.sanitize_params(%{
             "user" => %{"Password" => "x", "password_confirmation" => "x", "email" => "a@b"},
             "_csrf_token" => "t",
             "hashed_password" => "h",
             "accessToken" => "t"
           }) == %{
             "user" => %{
               "Password" => "[FILTERED]",
               "password_confirmation" => "[FILTERED]",
               "email" => "a@b"
             },
             "_csrf_token" => "[FILTERED]",
             "hashed_password" => "[FILTERED]",
             "accessToken" => "[FILTERED]"
           }
  end

  test "drops unreplayable LiveView internals from assigns only" do
    assigns = %{__changed__: %{}, uploads: %{}, streams: %{}, flash: %{}, count: 1}
    assert Default.sanitize_assigns(assigns) == %{flash: %{}, count: 1}
    assert Default.sanitize_params(%{"streams" => 1}) == %{"streams" => 1}
  end

  test "recurses into structs, lists and tuples" do
    account = %Account{name: "n", api_key: "k", profile: %{secret_answer: "s"}}

    assert Default.sanitize_assigns(%{items: [{:ok, account}]}) == %{
             items: [
               {:ok,
                %Account{
                  name: "n",
                  api_key: "[FILTERED]",
                  profile: %{secret_answer: "[FILTERED]"}
                }}
             ]
           }
  end

  test "keeps opaque standard library structs intact" do
    set = MapSet.new(["token"])
    now = DateTime.utc_now()
    assert Default.sanitize_assigns(%{set: set, now: now}) == %{set: set, now: now}
  end

  test "redact/2 masks pattern matches in nested strings, leaving structs alone" do
    patterns = [~r/\d{4}-\d{4}/, ~r/secret/]
    date = ~D[2026-01-01]

    assert PhoenixReplay.Sanitizer.redact(
             %{sql: "card 1234-5678", nested: [{"a secret", 1}], date: date, n: 1},
             patterns
           ) == %{sql: "card [REDACTED]", nested: [{"a [REDACTED]", 1}], date: date, n: 1}

    assert PhoenixReplay.Sanitizer.redact("1234-5678", []) == "1234-5678"
  end

  test "compacts changesets" do
    changeset =
      {%{}, %{name: :string, password: :string}}
      |> Ecto.Changeset.cast(%{"name" => "n", "password" => "p"}, [:name, :password])
      |> Ecto.Changeset.prepare_changes(& &1)

    %{changeset: sanitized} = Default.sanitize_assigns(%{changeset: changeset})

    assert sanitized.changes == %{name: "n", password: "[FILTERED]"}
    assert sanitized.params == %{"name" => "n", "password" => "[FILTERED]"}
    assert sanitized.prepare == []
  end

  test "compacts forms" do
    form = Phoenix.Component.to_form(%{"name" => "n", "password" => "p"}, as: :user)
    %{form: sanitized} = Default.sanitize_assigns(%{form: form})

    assert sanitized.source == %{"name" => "n", "password" => "[FILTERED]"}
    assert sanitized.params == %{"name" => "n", "password" => "[FILTERED]"}
    assert sanitized.options == []
  end
end
