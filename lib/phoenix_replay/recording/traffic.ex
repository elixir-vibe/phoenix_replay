defmodule PhoenixReplay.Recording.Traffic do
  @moduledoc """
  Where a visit came from, as Google Analytics tells it:

    * `:source` — the landing's `utm_source`, else the host of the site
      that referred it, else `"(direct)"`
    * `:medium` — its `utm_medium`, else `"referral"` when a site referred
      it, else `"(none)"`
    * `:campaign` — its `utm_campaign`, or `nil`

  All are `nil` when the visit's landing was not kept, without
  `PhoenixReplay.Plug` and `:context`. See
  `PhoenixReplay.Recording.Client.traffic/1`.
  """

  @type t :: %__MODULE__{
          source: String.t() | nil,
          medium: String.t() | nil,
          campaign: String.t() | nil
        }

  defstruct [:source, :medium, :campaign]

  @doc """
  Reads a source saved before 0.6: `"google / cpc / spring"`, or a lone
  referrer host or `utm_source`.
  """
  @spec from_legacy(String.t()) :: t()
  def from_legacy(source) when is_binary(source) do
    case String.split(source, " / ", parts: 3) do
      [source, medium | campaign] ->
        %__MODULE__{source: source, medium: medium, campaign: List.first(campaign)}

      # A referrer's host, or a lone utm_source.
      [one] ->
        %__MODULE__{
          source: one,
          medium: if(String.contains?(one, "."), do: "referral", else: "(none)")
        }
    end
  end
end
