defmodule PhoenixReplay.Export.Options do
  @moduledoc """
  What a video export shows and how it is encoded, as the player's export
  dialog and `mix phoenix_replay.export` choose it.

    * `:from` and `:to` — the range of the recording, in milliseconds;
      `nil` for its start or end
    * `:skip_idle` — shorten stretches without activity to the `:idle`
      configured
    * `:pointer` — draw the pointer; the page scrolls as recorded either way
    * `:rotated` — show the other orientation than recorded, without the
      pointer or the recorded scrolling, which fit only the recorded layout
    * `:size` — `:recorded`, the recorded pixel ratio up to `:max_dpr`;
      `:one`, one pixel per CSS pixel; or `:half`, half of that
    * `:fps` — frames per second: 15, 30 or 60
    * `:quality` — `:small`, `:balanced` or `:best`; `:balanced` is the
      configured `:crf`, and the others trade it for size or detail

  The defaults follow the `:export` configuration.
  """

  alias PhoenixReplay.Config

  @sizes %{"recorded" => :recorded, "1x" => :one, "half" => :half}
  @qualities %{"small" => :small, "balanced" => :balanced, "best" => :best}
  @frame_rates [15, 30, 60]
  # What idle stretches are shortened to when asked, if the configuration
  # keeps them whole.
  @idle 3_000
  # x264's CRF for the qualities other than the configured one.
  @crf %{small: 28, best: 18}

  @type size :: :recorded | :one | :half
  @type quality :: :small | :balanced | :best

  @type t :: %__MODULE__{
          from: non_neg_integer() | nil,
          to: non_neg_integer() | nil,
          skip_idle: boolean(),
          pointer: boolean(),
          rotated: boolean(),
          size: size(),
          fps: pos_integer(),
          quality: quality()
        }

  defstruct from: nil,
            to: nil,
            skip_idle: true,
            pointer: true,
            rotated: false,
            size: :recorded,
            fps: 30,
            quality: :balanced

  @doc "The frame rates offered."
  @spec frame_rates() :: [pos_integer()]
  def frame_rates, do: @frame_rates

  @doc "The defaults the `:export` configuration sets."
  @spec new(Config.export()) :: t()
  def new(export), do: %__MODULE__{skip_idle: export.idle != nil, fps: export.fps}

  @doc """
  Reads options from string params, as a form or command-line flags send
  them, onto the defaults: `"from"` and `"to"` in seconds, `"skip_idle"`,
  `"pointer"` and `"rotated"` as `"true"` or `"false"`, `"size"` as
  `"recorded"`, `"1x"` or `"half"`, `"fps"`, and `"quality"` as `"small"`,
  `"balanced"` or `"best"`. Missing params keep the defaults.
  """
  @spec parse(map(), Config.export()) :: {:ok, t()} | {:error, String.t()}
  def parse(params, export) do
    with {:ok, from} <- seconds(params["from"], "From"),
         {:ok, to} <- seconds(params["to"], "To"),
         :ok <- ordered(from, to),
         {:ok, fps} <- fps(params["fps"], export.fps),
         {:ok, size} <- choice(params["size"], @sizes, :recorded, "size"),
         {:ok, quality} <- choice(params["quality"], @qualities, :balanced, "quality") do
      defaults = new(export)

      {:ok,
       %{
         defaults
         | from: from,
           to: to,
           skip_idle: flag(params["skip_idle"], defaults.skip_idle),
           pointer: flag(params["pointer"], true),
           rotated: flag(params["rotated"], false),
           fps: fps,
           size: size,
           quality: quality
       }}
    end
  end

  @doc """
  The `:export` configuration the options make: the frame rate, the idle
  time, the pixel ratio, the quality and a `:scale` for the encoder.
  """
  @spec apply(t(), Config.export()) :: map()
  def apply(%__MODULE__{} = options, export) do
    Map.merge(export, %{
      fps: options.fps,
      idle: if(options.skip_idle, do: export.idle || @idle),
      max_dpr: if(options.size == :recorded, do: export.max_dpr, else: 1),
      scale: if(options.size == :half, do: 0.5, else: 1),
      crf: Map.get(@crf, options.quality, export.crf)
    })
  end

  defp seconds(blank, _field) when blank in [nil, ""], do: {:ok, nil}

  defp seconds(value, field) do
    case Float.parse(value) do
      {seconds, ""} when seconds >= 0 -> {:ok, round(seconds * 1_000)}
      _invalid -> {:error, "#{field} must be a number of seconds."}
    end
  end

  defp ordered(from, to) when is_integer(from) and is_integer(to) and from >= to,
    do: {:error, "From must come before To."}

  defp ordered(_from, _to), do: :ok

  defp fps(blank, default) when blank in [nil, ""], do: {:ok, default}

  defp fps(value, _default) do
    case Integer.parse(value) do
      {fps, ""} when fps in @frame_rates -> {:ok, fps}
      _invalid -> {:error, "The frame rate must be one of #{Enum.join(@frame_rates, ", ")}."}
    end
  end

  defp choice(blank, _choices, default, _name) when blank in [nil, ""], do: {:ok, default}

  defp choice(value, choices, _default, name) do
    case Map.fetch(choices, value) do
      {:ok, choice} -> {:ok, choice}
      :error -> {:error, "Unknown #{name} #{inspect(value)}."}
    end
  end

  defp flag(value, default) when value in [nil, ""], do: default
  defp flag(value, _default), do: value in ["true", "on"]
end
