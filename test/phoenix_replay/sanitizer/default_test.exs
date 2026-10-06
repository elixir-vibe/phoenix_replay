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

  test "filters payment, identity and one-time code fields, by whole word where short" do
    params = %{
      "card_number" => "4242",
      "creditCardNumber" => "4242",
      "card_cvv" => "123",
      "cvc" => "123",
      "ssn" => "078",
      "pinCode" => "1234",
      "otp" => "999999",
      "one_time_code" => "999999",
      # Words that only contain the short names are kept.
      "shipping" => "fast",
      "footprint" => "small",
      "spinner" => "on"
    }

    assert %{
             "card_number" => "[FILTERED]",
             "creditCardNumber" => "[FILTERED]",
             "card_cvv" => "[FILTERED]",
             "cvc" => "[FILTERED]",
             "ssn" => "[FILTERED]",
             "pinCode" => "[FILTERED]",
             "otp" => "[FILTERED]",
             "one_time_code" => "[FILTERED]",
             "shipping" => "fast",
             "footprint" => "small",
             "spinner" => "on"
           } = Default.sanitize_params(params)
  end

  test "keeps assigns that only have a short name as a word, which params filter" do
    values = %{pin: %{lat: 1, lng: 2}, otp_app: :my_app, pin_code: "1234", password: "x"}

    assert %{pin: %{lat: 1}, otp_app: :my_app, pin_code: "1234", password: "[FILTERED]"} =
             Default.sanitize_assigns(values)

    assert %{pin: "[FILTERED]", otp_app: "[FILTERED]", pin_code: "[FILTERED]"} =
             Default.sanitize_params(values)
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
