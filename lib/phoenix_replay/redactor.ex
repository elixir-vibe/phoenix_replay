defmodule PhoenixReplay.Redactor do
  @moduledoc """
  Behaviour for masking sensitive text in recordings before they are stored.

  A `PhoenixReplay.Sanitizer` runs inside your LiveViews on every event, so
  it filters by key, which is cheap. Values such as an email address typed
  into a form, a card number in a log message or a phone number in SQL
  carry no telling key, and finding them in text takes longer. A redactor
  finds them when a session is saved, in a background task, so its cost
  never reaches your users.

  A redactor receives one string at a time. `redact_term/2` walks maps,
  lists, tuples and structs, keeping struct types so recorded templates
  still render, and leaves opaque values such as `Date` and `Decimal` as
  they are.

  Configure it with `:redact`:

      # Regexes, matched by PhoenixReplay.Redactor.Patterns
      config :phoenix_replay, redact: [~r/\\b\\d{13,19}\\b/]

      # Detection with Obscura, an optional dependency
      config :phoenix_replay, redact: {PhoenixReplay.Redactor.Obscura, []}

  Recordings are redacted when they are saved and when the dashboard
  opens a session that is still running, so stored recordings and live
  sessions show the same values. A redactor that fails stops the save
  rather than storing unredacted data.
  """

  alias PhoenixReplay.Recording
  alias PhoenixReplay.Recording.Event

  @typedoc "A redactor module and its options."
  @type t :: {module(), keyword()}

  @typedoc "Called with the number of events redacted so far and the total."
  @type progress :: (non_neg_integer(), non_neg_integer() -> any())

  @doc "Redacts sensitive values in `text`."
  @callback redact(text :: String.t(), opts :: keyword()) :: {:ok, String.t()} | {:error, term()}

  # As PhoenixReplay.Sanitizer.Default keeps them, but for URI: its path,
  # query and user info hold whatever was typed into them.
  @opaque_structs PhoenixReplay.Recording.Value.opaque_structs() -- [URI]

  @doc """
  Redacts every part of `recording` that holds recorded values: its URL,
  params, session, the URL the user came from, the user agent, captured
  headers and landing, and the data of each event. The viewport and tab id
  are kept as they are.

  Without a redactor, the recording is returned as it is. A failure is
  `{:error, :redaction_failed}`, without the redactor's reason, which may
  quote the text it could not redact.

  ## Options

    * `:progress` — a `t:progress/0` function, called after each event
  """
  @spec redact_recording(Recording.t(), t() | nil, keyword()) ::
          {:ok, Recording.t()} | {:error, :redaction_failed}
  def redact_recording(recording, redactor, opts \\ [])
  def redact_recording(%Recording{} = recording, nil, _opts), do: {:ok, recording}

  def redact_recording(%Recording{} = recording, redactor, opts) do
    progress = Keyword.get(opts, :progress, fn _done, _total -> :ok end)
    total = length(recording.events)

    with {:ok, url} <- redact_term(recording.url, redactor),
         {:ok, params} <- redact_term(recording.params, redactor),
         {:ok, session} <- redact_term(recording.session, redactor),
         {:ok, navigated_from} <- redact_term(recording.client.navigated_from, redactor),
         {:ok, user_agent} <- redact_term(recording.client.user_agent, redactor),
         {:ok, headers} <- redact_term(recording.client.headers, redactor),
         {:ok, landing} <- redact_term(recording.client.landing, redactor),
         {:ok, events} <- redact_events(recording.events, redactor, progress, total) do
      client = %{
        recording.client
        | navigated_from: navigated_from,
          user_agent: user_agent,
          headers: headers,
          landing: landing
      }

      {:ok,
       %{recording | url: url, params: params, session: session, client: client, events: events}}
    else
      {:error, _reason} -> {:error, :redaction_failed}
    end
  end

  @doc """
  Redacts every string within `term`, recursing into maps, lists, tuples
  and structs. Map keys are kept as they are.
  """
  @spec redact_term(term(), t()) :: {:ok, term()} | {:error, term()}
  def redact_term(text, {module, opts}) when is_binary(text), do: module.redact(text, opts)
  def redact_term(%module{} = struct, _redactor) when module in @opaque_structs, do: {:ok, struct}

  def redact_term(%module{} = struct, redactor) do
    with {:ok, fields} <- redact_term(Map.from_struct(struct), redactor) do
      {:ok, Map.put(fields, :__struct__, module)}
    end
  end

  def redact_term(map, redactor) when is_map(map) do
    map
    |> Map.to_list()
    |> redact_all(fn {key, value} ->
      with {:ok, value} <- redact_term(value, redactor), do: {:ok, {key, value}}
    end)
    |> map_ok(&Map.new/1)
  end

  def redact_term(list, redactor) when is_list(list) do
    if List.improper?(list),
      do: {:ok, list},
      else: redact_all(list, &redact_term(&1, redactor))
  end

  def redact_term(tuple, redactor) when is_tuple(tuple) do
    tuple |> Tuple.to_list() |> redact_term(redactor) |> map_ok(&List.to_tuple/1)
  end

  def redact_term(term, _redactor), do: {:ok, term}

  defp redact_events(events, redactor, progress, total) do
    events
    |> Enum.with_index(1)
    |> redact_all(fn {%Event{data: data} = event, done} ->
      with {:ok, data} <- redact_term(data, redactor) do
        progress.(done, total)
        {:ok, %{event | data: data}}
      end
    end)
  end

  defp redact_all(items, fun) do
    items
    |> Enum.reduce_while({:ok, []}, fn item, {:ok, acc} ->
      case fun.(item) do
        {:ok, redacted} -> {:cont, {:ok, [redacted | acc]}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
    |> map_ok(&Enum.reverse/1)
  end

  defp map_ok({:ok, value}, fun), do: {:ok, fun.(value)}
  defp map_ok({:error, _reason} = error, _fun), do: error
end
