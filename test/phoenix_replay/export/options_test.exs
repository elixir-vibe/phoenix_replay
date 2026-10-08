defmodule PhoenixReplay.Export.OptionsTest do
  use ExUnit.Case, async: true

  alias PhoenixReplay.Config
  alias PhoenixReplay.Export.Options

  @export Config.new(export: [endpoint: MyAppWeb.Endpoint]).export

  test "defaults follow the configuration" do
    assert %Options{skip_idle: true, pointer: true, fps: 30, size: :recorded} =
             Options.new(@export)

    assert %Options{skip_idle: false, fps: 15} =
             Options.new(%{@export | idle: nil, fps: 15})
  end

  test "reads what a form or the command line sends" do
    params = %{
      "from" => "1.5",
      "to" => "4",
      "skip_idle" => "false",
      "pointer" => "false",
      "size" => "half",
      "fps" => "60",
      "quality" => "best"
    }

    assert {:ok,
            %Options{
              from: 1_500,
              to: 4_000,
              skip_idle: false,
              pointer: false,
              size: :half,
              fps: 60,
              quality: :best
            }} = Options.parse(params, @export)

    # Blank and missing params keep the defaults.
    assert {:ok, %Options{from: nil, to: nil, pointer: true, fps: 30}} =
             Options.parse(%{"from" => "", "fps" => ""}, @export)
  end

  test "explains what it cannot read" do
    assert {:error, "From must come before To."} =
             Options.parse(%{"from" => "5", "to" => "2"}, @export)

    assert {:error, "To must be a number of seconds."} = Options.parse(%{"to" => "soon"}, @export)

    assert {:error, "The frame rate must be one of 15, 30, 60."} =
             Options.parse(%{"fps" => "24"}, @export)

    assert {:error, ~s(Unknown size "4k".)} = Options.parse(%{"size" => "4k"}, @export)
  end

  test "turns into the export settings the render uses" do
    {:ok, options} =
      Options.parse(%{"size" => "half", "quality" => "small", "fps" => "15"}, @export)

    assert %{fps: 15, idle: 3_000, max_dpr: 1, scale: 0.5, crf: 28} =
             Options.apply(options, @export)

    {:ok, options} = Options.parse(%{"skip_idle" => "false"}, @export)
    assert %{idle: nil, max_dpr: 2, scale: 1, crf: 23} = Options.apply(options, @export)
  end
end
