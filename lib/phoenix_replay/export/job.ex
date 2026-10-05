defmodule PhoenixReplay.Export.Job do
  @moduledoc """
  A video export: which recording, how far it got and where the video is.

  `status` moves from `:queued` to `:running`, then to `:done` with the
  video at `path`, or to `:failed` with an `error` to show. A cancelled
  job is `:cancelled`, after `:cancelling` while a running one stops.
  `progress` is a percentage.
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
          error: String.t() | nil,
          finished_at: integer() | nil
        }

  @enforce_keys [:id, :recording_id, :options]
  defstruct [
    :id,
    :recording_id,
    :options,
    :path,
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

  @doc "Whether the export has finished, either way."
  @spec finished?(t()) :: boolean()
  def finished?(%__MODULE__{status: status}), do: status in [:done, :failed, :cancelled]

  @doc "Whether the export can still be cancelled."
  @spec cancellable?(t()) :: boolean()
  def cancellable?(%__MODULE__{status: status}), do: status in [:queued, :running]
end
