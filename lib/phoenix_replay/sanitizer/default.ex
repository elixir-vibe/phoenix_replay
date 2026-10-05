defmodule PhoenixReplay.Sanitizer.Default do
  @moduledoc """
  Default `PhoenixReplay.Sanitizer`.

    * Replaces the value of any key whose name contains `password`, `token`,
      `secret`, `api_key`, `private_key`, `credential`, `card_number`,
      `credit_card` or `one_time`, or has `cvv`, `cvc`, `csc`, `ssn`, `pin`
      or `otp` as a word of its own, such as `card_cvv` or `pinCode` but
      not `shipping`, with `"[FILTERED]"`. Keys are kept so recorded
      templates still find them.
    * Recurses into maps, lists, tuples and structs, and compacts
      `Ecto.Changeset` and `Phoenix.HTML.Form` runtime metadata.

  Opaque standard-library structs such as `MapSet` and `DateTime`, and
  `URI`, are kept as they are: no key in them tells a secret apart.
  LiveView internals that cannot be replayed never reach a sanitizer.
  """

  @behaviour PhoenixReplay.Sanitizer

  @filtered "[FILTERED]"
  @sensitive ~w(password token secret api_key apikey private_key credential card_number
                cardnumber credit_card creditcard one_time)
  # Short names that would match inside other words, so only whole words.
  @sensitive_words ~w(cvv cvc csc ssn pin otp)
  @opaque_structs [
    Date,
    DateTime,
    Decimal,
    MapSet,
    NaiveDateTime,
    Range,
    Regex,
    Time,
    URI,
    Version
  ]

  @impl true
  def sanitize_assigns(assigns) when is_map(assigns), do: sanitize_map(assigns)

  @impl true
  def sanitize_params(params) when is_map(params), do: sanitize_map(params)

  defp sanitize(%module{} = struct) when module in @opaque_structs, do: struct

  defp sanitize(%{__struct__: Ecto.Changeset} = changeset) do
    %{
      changeset
      | data: sanitize(changeset.data),
        changes: sanitize(changeset.changes),
        params: sanitize(changeset.params),
        prepare: [],
        repo: nil,
        repo_opts: []
    }
  end

  defp sanitize(%Phoenix.HTML.Form{} = form) do
    %{
      form
      | source: sanitize(form.source),
        data: sanitize(form.data),
        params: sanitize(form.params),
        options: []
    }
  end

  defp sanitize(%module{} = struct) do
    struct
    |> Map.from_struct()
    |> sanitize_map()
    |> Map.put(:__struct__, module)
  end

  defp sanitize(map) when is_map(map), do: sanitize_map(map)
  defp sanitize(list) when is_list(list), do: Enum.map(list, &sanitize/1)

  defp sanitize(tuple) when is_tuple(tuple),
    do: tuple |> Tuple.to_list() |> Enum.map(&sanitize/1) |> List.to_tuple()

  defp sanitize(value), do: value

  defp sanitize_map(map) do
    Map.new(map, fn {key, value} ->
      if sensitive?(key), do: {key, @filtered}, else: {key, sanitize(value)}
    end)
  end

  defp sensitive?(key) when is_atom(key), do: key |> Atom.to_string() |> sensitive?()

  defp sensitive?(key) when is_binary(key) do
    words =
      key
      |> String.split(~r/[^[:alnum:]]+|(?<=[[:lower:]])(?=[[:upper:]])/u)
      |> Enum.map(&String.downcase/1)

    key = String.downcase(key)

    Enum.any?(@sensitive, &String.contains?(key, &1)) or
      Enum.any?(words, &(&1 in @sensitive_words))
  end

  defp sensitive?(_key), do: false
end
