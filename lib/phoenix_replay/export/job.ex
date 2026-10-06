defmodule PhoenixReplay.Export.Job do
  @moduledoc """
  A video export: which recording, how far it got and where the video is.

  `status` moves from `:queued` to `:running`, then to `:done` with the
  video at `path`, or to `:failed` with an `error` to show. A cancelled
  job is `:cancelled`, after `:cancelling` while a running one stops.
  `progress` is a percentage. `node` is the node that renders the video,
  whose disk it is on.
  """

  alias PhoenixReplay.Export.Options
  alias PhoenixReplay.Recording

  @type id :: String.t()
  @type status :: :queued | :running | :cancelling | :done | :failed | :cancelled

  @type t :: %__MODULE__{
          id: id(),
          recording_id: Recording.id(),
          options: Options.t(),
          status: status(),
          progress: 0..100,
          path: Path.t() | nil,
          node: node() | nil,
          error: String.t() | nil,
          finished_at: integer() | nil
        }

  @enforce_keys [:id, :recording_id, :options]
  defstruct [
    :id,
    :recording_id,
    :options,
    :path,
    :node,
    :error,
    :finished_at,
    status: :queued,
    progress: 0
  ]

  @doc "A queued export of a recording, with the options it was asked for."
  @spec new(Recording.id(), Options.t()) :: t()
  def new(recording_id, %Options{} = options),
    do: %__MODULE__{
      id: Base.url_encode64(:crypto.strong_rand_bytes(12), padding: false),
      recording_id: recording_id,
      options: options
    }

  @doc """
  Whether `name`, a file or directory in the export directory, is one an
  export made: `<id>.mp4` or the `<id>` directory of its screenshots, for
  an id `new/2` made or one of `PhoenixReplay.Export.Queue.Oban`'s, such as
  `oban-42`.
  """
  @spec file?(String.t()) :: boolean()
  def file?(name), do: Regex.match?(~r/\A([A-Za-z0-9_-]{16}|oban-\d+)(\.mp4)?\z/, name)

  @doc "Whether the export has finished, either way."
  @spec finished?(t()) :: boolean()
  def finished?(%__MODULE__{status: status}), do: status in [:done, :failed, :cancelled]

  @doc "Whether the export can still be cancelled."
  @spec cancellable?(t()) :: boolean()
  def cancellable?(%__MODULE__{status: status}), do: status in [:queued, :running]
end
