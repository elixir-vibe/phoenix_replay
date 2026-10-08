defmodule PhoenixReplay.Web.Highlight do
  @moduledoc """
  Highlights code in the player with `Lumis`: collected SQL, and recorded
  values as `PhoenixReplay.Recording.Value.inspect/2` writes them.

  Tokens become spans with Lumis's `l-` classes, which the dashboard's
  stylesheet colours from its own palette, so code follows the light and
  dark themes. Text Lumis cannot parse is shown as it is.
  """

  require Logger

  alias PhoenixReplay.Recording.Value

  @type language :: :elixir | :sql

  # The grammars the player uses; Elixir injects `comment`.
  @languages ~w(elixir sql comment)

  @doc """
  Compiles the grammars in the background, once per VM, so the first
  replay does not wait for them. The dashboard calls it when it mounts;
  an application that never opens the dashboard never compiles them.
  """
  @spec warm() :: :ok
  def warm do
    unless :persistent_term.get({__MODULE__, :warm}, false) do
      :persistent_term.put({__MODULE__, :warm}, true)
      _loading = Lumis.Languages.async_load(@languages)
    end

    :ok
  end

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

  @doc "Highlights a recorded value as `PhoenixReplay.Recording.Value.inspect/2` writes it."
  @spec term(term(), keyword()) :: Phoenix.HTML.safe()
  def term(value, opts \\ []), do: value |> Value.inspect(opts) |> code(:elixir)
end
