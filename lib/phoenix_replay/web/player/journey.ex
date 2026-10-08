defmodule PhoenixReplay.Web.Player.Journey do
  @moduledoc """
  The other sessions of a recording's browser tab, for the player's Visit
  tab: where this one falls among them, and links to the one before and
  after. Only the sessions the viewer may list are counted.
  """

  alias PhoenixReplay.Catalog
  alias PhoenixReplay.Recording
  alias PhoenixReplay.Recording.Filter
  alias PhoenixReplay.Web.Context

  # The most saved sessions of one tab read.
  @limit 200

  @type t :: %{
          tab_path: String.t(),
          position: pos_integer(),
          total: pos_integer(),
          previous: String.t() | nil,
          next: String.t() | nil
        }

  @doc """
  The journey of `recording`'s browser tab, oldest first, or `nil` when it
  was the tab's only session, or did not say which tab it ran in.
  """
  @spec of(Phoenix.LiveView.Socket.t(), Recording.t()) :: t() | nil
  def of(socket, %Recording{id: id, client: %{tab: tab}}) when is_binary(tab) do
    %{config: config} = context = socket.assigns.context
    filter = %Filter{tab: tab}
    now = System.system_time(:millisecond)
    {stored, _total} = Catalog.query(config, filter, now: now, limit: @limit)

    sessions =
      (Catalog.live(filter, now) ++ stored)
      |> Enum.uniq_by(& &1.id)
      |> Enum.filter(&Context.allowed?(socket, :list, &1))
      |> Enum.sort_by(& &1.connected_at)

    case {Enum.find_index(sessions, &(&1.id == id)), sessions} do
      {index, [_first, _second | _rest]} when is_integer(index) ->
        %{
          tab_path: Context.path(context, []) <> "?" <> URI.encode_query(%{"tab" => tab}),
          position: index + 1,
          total: length(sessions),
          previous: if(index > 0, do: Context.path(context, [Enum.at(sessions, index - 1).id])),
          next: (next = Enum.at(sessions, index + 1)) && Context.path(context, [next.id])
        }

      _alone ->
        nil
    end
  end

  def of(_socket, _recording), do: nil
end
