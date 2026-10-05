defmodule PhoenixReplay.Recording do
  @moduledoc """
  A recorded LiveView session.

  Holds the session metadata and an ordered list of `PhoenixReplay.Recording.Event`s.
  Use `PhoenixReplay.Recording.Timeline` to reconstruct state at a point in time.

  `dropped` counts collected events left out once a collector reached its
  `:limit`, keyed by collector name, such as `"my_app.repo.query"` or `"log"`.

  `client` describes the browser and the visit; see
  `PhoenixReplay.Recording.Client`.
  """

  alias PhoenixReplay.Recording.Client
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
          client: Client.t()
        }

  @type viewport :: %{width: pos_integer(), height: pos_integer(), dpr: number()}

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
    client: %Client{}
  ]

  @doc """
  Brings a recording stored by an earlier version up to date.
  `PhoenixReplay.Storage.Codec` calls it on every recording it decodes.
  """
  @spec upgrade(t()) :: t()
  def upgrade(%__MODULE__{client: client} = recording),
    do: %{recording | client: Client.upgrade(client)}

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
