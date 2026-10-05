defmodule PhoenixReplay.Web.Highlight do
  @moduledoc """
  Highlights code in the player with `Lumis`: collected SQL, and recorded
  values as `inspect/2` writes them.

  Tokens become spans with Lumis's `l-` classes, which the dashboard's
  stylesheet colours from its own palette, so code follows the light and
  dark themes. Text Lumis cannot parse is shown as it is.
  """

  require Logger

  @type language :: :elixir | :sql

  @doc "Highlights `source` written in `language`, for use inside `<code>` or `<pre>`."
  @spec code(String.t(), language()) :: Phoenix.HTML.safe()
  def code(source, language) when is_binary(source) do
    formatter = {:html_linked, language: Atom.to_string(language), structure: :inline}

    case Lumis.highlight(source, formatter: formatter) do
      {:ok, html} ->
        {:safe, html}

      {:error, reason} ->
        Logger.debug("PhoenixReplay: could not highlight #{language}: #{inspect(reason)}")
        Phoenix.HTML.html_escape(source)
    end
  end

  @doc "Highlights a value as `inspect/2` writes it with `opts`."
  @spec term(term(), keyword()) :: Phoenix.HTML.safe()
  def term(value, opts \\ []), do: value |> inspect(opts) |> code(:elixir)
end
