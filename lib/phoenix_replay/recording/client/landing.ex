defmodule PhoenixReplay.Recording.Client.Landing do
  @moduledoc """
  The first request of a visit, kept by `PhoenixReplay.Plug` when
  `:context` asks for it: its path, when it happened, the campaign params
  it carried and the site that referred it.
  """

  @type t :: %__MODULE__{
          path: String.t(),
          at: integer(),
          params: %{String.t() => String.t()},
          referrer: String.t() | nil
        }

  @enforce_keys [:path, :at]
  defstruct [:path, :at, :referrer, params: %{}]
end
