defmodule PhoenixReplay.Sanitizer.Default do
  @moduledoc """
  Default `PhoenixReplay.Sanitizer`.

    * Replaces the value of any key whose name contains `password`, `token`,
      `secret`, `api_key`, `private_key`, `credential`, `card_number`,
      `credit_card` or `one_time` with `"[FILTERED]"`. Keys are kept so
      recorded templates still find them.
    * In params, which include what users type into form controls, also
      filters keys that have `cvv`, `cvc`, `csc`, `ssn`, `pin` or `otp` as
      a word of their own, such as `card_cvv` or `pinCode` but not
      `shipping`. Assigns keep them: an assign named `:pin` or `:otp_app`
      is usually not a secret, and a filtered one can break the replay.
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
  @opaque_structs PhoenixReplay.Recording.Value.opaque_structs()

  @impl true
  def sanitize_assigns(assigns) when is_map(assigns), do: sanitize_map(assigns, false)

  @impl true
  def sanitize_params(params) when is_map(params), do: sanitize_map(params, true)

  # `words?` also filters the short names, for params.
  defp sanitize(%module{} = struct, _words?) when module in @opaque_structs, do: struct

  defp sanitize(%{__struct__: Ecto.Changeset} = changeset, words?) do
    %{
      changeset
      | data: sanitize(changeset.data, words?),
        changes: sanitize(changeset.changes, words?),
        params: sanitize(changeset.params, words?),
        prepare: [],
        repo: nil,
        repo_opts: []
    }
  end

  defp sanitize(%Phoenix.HTML.Form{} = form, words?) do
    %{
      form
      | source: sanitize(form.source, words?),
        data: sanitize(form.data, words?),
        params: sanitize(form.params, words?),
        options: []
    }
  end

  defp sanitize(%module{} = struct, words?) do
    struct
    |> Map.from_struct()
    |> sanitize_map(words?)
    |> Map.put(:__struct__, module)
  end

  defp sanitize(map, words?) when is_map(map), do: sanitize_map(map, words?)
  defp sanitize(list, words?) when is_list(list), do: Enum.map(list, &sanitize(&1, words?))

  defp sanitize(tuple, words?) when is_tuple(tuple),
    do: tuple |> Tuple.to_list() |> Enum.map(&sanitize(&1, words?)) |> List.to_tuple()

  defp sanitize(value, _words?), do: value

  defp sanitize_map(map, words?) do
    Map.new(map, fn {key, value} ->
      if sensitive?(key, words?), do: {key, @filtered}, else: {key, sanitize(value, words?)}
    end)
  end

  # It runs for every key of every recorded assign, so it matches every name
  # in one pass, and looks for word boundaries only when a short name occurs.
  defp sensitive?(key, words?) when is_atom(key),
    do: key |> Atom.to_string() |> sensitive?(words?)

  defp sensitive?(key, words?) when is_binary(key) do
    lower = String.downcase(key, :ascii)

    occurs?(lower, :names) or (words? and occurs?(lower, :words) and word?(key, lower))
  end

  defp sensitive?(_key, _words?), do: false

  defp occurs?(lower, patterns), do: :binary.match(lower, pattern(patterns)) != :nomatch

  # Compiled once: compiling a list of names for each key costs more than
  # matching it.
  defp pattern(patterns) do
    key = {__MODULE__, patterns}

    case :persistent_term.get(key, nil) do
      nil ->
        names = if patterns == :names, do: @sensitive, else: @sensitive_words
        compiled = :binary.compile_pattern(names)
        :persistent_term.put(key, compiled)
        compiled

      compiled ->
        compiled
    end
  end

  defp word?(key, lower) do
    lower
    |> :binary.matches(pattern(:words))
    |> Enum.any?(fn {at, length} -> starts_word?(key, at) and ends_word?(key, at + length) end)
  end

  # A word starts after a separator or at a capital, as `pinCode` or
  # `userPin`, and ends before a separator, a capital, or the end.
  defp starts_word?(_key, 0), do: true

  defp starts_word?(key, at),
    do: not alnum?(:binary.at(key, at - 1)) or upper?(:binary.at(key, at))

  defp ends_word?(key, at) when at == byte_size(key), do: true
  defp ends_word?(key, at), do: not alnum?(:binary.at(key, at)) or upper?(:binary.at(key, at))

  defp alnum?(byte), do: byte in ?a..?z or byte in ?A..?Z or byte in ?0..?9
  defp upper?(byte), do: byte in ?A..?Z
end
