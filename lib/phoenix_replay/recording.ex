defmodule PhoenixReplay.Recording do
  @moduledoc """
  A recorded LiveView session.

  Holds the session metadata and an ordered list of `PhoenixReplay.Recording.Event`s.
  Use `PhoenixReplay.Recording.Timeline` to reconstruct state at a point in time.

  `dropped` counts collected events left out once a collector reached its
  `:limit`, keyed by collector name, such as `"my_app.repo.query"` or `"log"`.

  `client` describes the browser, when it told PhoenixReplay (see
  `PhoenixReplay.Capture.Client`):

    * `:viewport` — `%{width: integer, height: integer, dpr: number}` when
      the LiveView connected; later changes are `:viewport` events
    * `:user_agent` — the `User-Agent` header, when the endpoint's socket
      lists `:user_agent` in its `:connect_info`
    * `:tab` — an id of the browser tab, shared by the tab's sessions
    * `:referer` — the URL the user came from by live navigation
    * `:headers` — request headers listed in `:context`, kept by
      `PhoenixReplay.Plug`
    * `:landing` — the visit's landing request, when `:context` asks for
      it: `%{path: String.t(), at: integer, params: map, referrer:
      String.t() | nil}`
  """

  alias PhoenixReplay.Recording.Event

  @type id :: String.t()

  @type t :: %__MODULE__{
          id: id(),
          view: module(),
          url: String.t() | nil,
          params: map(),
          session: map(),
          connected_at: integer(),
          events: [Event.t()],
          dropped: %{String.t() => pos_integer()},
          client: client()
        }

  @type viewport :: %{width: pos_integer(), height: pos_integer(), dpr: number()}

  @type client :: %{
          viewport: viewport() | nil,
          user_agent: String.t() | nil,
          tab: String.t() | nil,
          referer: String.t() | nil,
          headers: %{String.t() => String.t()},
          landing: landing() | nil
        }

  @type landing :: %{
          path: String.t(),
          at: integer(),
          params: %{String.t() => String.t()},
          referrer: String.t() | nil
        }

  @enforce_keys [:id, :view, :connected_at]
  defstruct [
    :id,
    :view,
    :url,
    :connected_at,
    params: %{},
    session: %{},
    events: [],
    dropped: %{},
    client: %{
      viewport: nil,
      user_agent: nil,
      tab: nil,
      referer: nil,
      headers: %{},
      landing: nil
    }
  ]

  @doc "Generates a URL-safe random recording id."
  @spec generate_id() :: id()
  def generate_id, do: Base.url_encode64(:crypto.strong_rand_bytes(16), padding: false)

  @doc "Returns true when `id` has the shape produced by `generate_id/0`."
  @spec valid_id?(term()) :: boolean()
  def valid_id?(id) when is_binary(id) and byte_size(id) in 1..64,
    do: id |> String.to_charlist() |> Enum.all?(&id_char?/1)

  def valid_id?(_id), do: false

  defp id_char?(char), do: char in ?a..?z or char in ?A..?Z or char in ?0..?9 or char in ~c"-_"
end
