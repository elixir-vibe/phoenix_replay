defmodule PhoenixReplay.Redactor.ObscuraTest do
  use ExUnit.Case, async: true

  alias PhoenixReplay.Redactor
  alias PhoenixReplay.Redactor.Obscura, as: ObscuraRedactor

  test "replaces personal data with placeholders" do
    assert ObscuraRedactor.redact("Charge jane@example.com card 4111 1111 1111 1111", []) ==
             {:ok, "Charge [EMAIL] card [CREDIT_CARD]"}
  end

  test "leaves module and file names alone by default" do
    assert ObscuraRedactor.redact("rendered phoenix.html for MyApp.Web", []) ==
             {:ok, "rendered phoenix.html for MyApp.Web"}
  end

  test "takes Obscura options" do
    assert ObscuraRedactor.redact("jane@example.com at 10.0.0.1", entities: [:email]) ==
             {:ok, "[EMAIL] at 10.0.0.1"}
  end

  test "redacts nested terms through Redactor.redact_term/2" do
    assert Redactor.redact_term(%{"email" => "jane@example.com"}, {ObscuraRedactor, []}) ==
             {:ok, %{"email" => "[EMAIL]"}}
  end
end
