defmodule PhoenixReplay.Web.Playback do
  @moduledoc """
  Messaging between a player and its replay frame.

  Each player opens a private channel with an unguessable name and passes it
  to its frame, so viewers of the same recording never drive each other's
  frames. When the frame connects it announces itself and the player answers
  with the current position, preceded by the recording itself for a live
  session, which the frame does not read from the buffer.
  """

  alias PhoenixReplay.Recording
  alias PhoenixReplay.Recording.{Pointer, State}

  @type channel :: String.t()

  @doc """
  Lays a recording out for playback, the same way for the player and its
  frame, so an index means the same event in both: the pointer track is
  taken out, to be drawn over the frame, and client state is spread into
  an event per entry. See `PhoenixReplay.Recording.Pointer.split/1` and
  `PhoenixReplay.Recording.State.spread/1`.
  """
  @spec prepare(Recording.t()) :: {Recording.t(), Pointer.t()}
  def prepare(%Recording{} = recording) do
    {recording, pointer} = Pointer.split(recording)
    {State.spread(recording), pointer}
  end

  @doc "Generates a new channel name."
  @spec new_channel() :: channel()
  def new_channel, do: Base.url_encode64(:crypto.strong_rand_bytes(16), padding: false)

  @doc "Subscribes the caller to `channel`."
  @spec subscribe(channel()) :: :ok | {:error, term()}
  def subscribe(channel), do: Phoenix.PubSub.subscribe(PhoenixReplay.PubSub, topic(channel))

  @doc "Hands the frame a live session's redacted recording."
  @spec load(channel(), PhoenixReplay.Recording.t()) :: :ok
  def load(channel, recording), do: broadcast(channel, {:load, recording})

  @doc "Tells the frame to show the event at `index`."
  @spec seek(channel(), non_neg_integer()) :: :ok
  def seek(channel, index), do: broadcast(channel, {:seek, index})

  @doc "Tells the player that its frame connected."
  @spec frame_ready(channel()) :: :ok
  def frame_ready(channel), do: broadcast(channel, :frame_ready)

  defp broadcast(channel, message) do
    Phoenix.PubSub.broadcast_from(
      PhoenixReplay.PubSub,
      self(),
      topic(channel),
      {__MODULE__, message}
    )
  end

  defp topic(channel), do: "phoenix_replay:playback:" <> channel
end
