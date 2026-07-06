defmodule PhoenixReplay.Storage.SerializerTest do
  use ExUnit.Case, async: true

  alias PhoenixReplay.Recording
  alias PhoenixReplay.Storage.Serializer

  defp sample_recording do
    %Recording{
      id: "test-123",
      view: PhoenixReplay.TestLive.Counter,
      url: "http://localhost/counter",
      params: %{},
      session: %{},
      connected_at: 1_700_000_000_000,
      events: [
        {0, :mount, %{assigns: %{count: 0}}},
        {100, :event, %{name: "inc"}},
        {200, :assigns, %{delta: %{count: 1}}}
      ]
    }
  end

  defp recording_with_form do
    %Recording{
      id: "form-test",
      view: PhoenixReplay.TestLive.Form,
      url: "http://localhost/form",
      params: %{},
      session: %{},
      connected_at: 1_700_000_000_000,
      events: [
        {0, :mount, %{assigns: %{name: ""}}},
        {100, :event, %{name: "validate", params: %{"name" => "Hi"}}},
        {200, :assigns,
         %{
           delta: %{
             form: %Phoenix.HTML.Form{
               source: %{"name" => "Hi"},
               impl: Phoenix.HTML.FormData.Map,
               id: "form",
               name: "form",
               data: %{name: ""},
               action: :validate,
               hidden: [],
               params: %{"name" => "Hi"},
               errors: [],
               options: [],
               index: nil
             }
           }
         }}
      ]
    }
  end

  test "ETF roundtrip preserves all data" do
    rec = sample_recording()
    {:ok, encoded} = Serializer.encode(rec, :etf)
    {:ok, decoded} = Serializer.decode(encoded, :etf)

    assert decoded.id == rec.id
    assert decoded.view == rec.view
    assert decoded.connected_at == rec.connected_at
    assert decoded.events == rec.events
    assert <<131, 80, _rest::binary>> = encoded
  end

  test "JSON roundtrip preserves essential data" do
    rec = sample_recording()
    {:ok, encoded} = Serializer.encode(rec, :json)
    assert is_binary(encoded)
    assert String.contains?(encoded, "test-123")

    {:ok, decoded} = Serializer.decode(encoded, :json)
    assert decoded.id == rec.id
    assert decoded.view == rec.view
    assert decoded.connected_at == rec.connected_at
    assert length(decoded.events) == 3

    {offset, type, _payload} = hd(decoded.events)
    assert offset == 0
    assert type == :mount
  end

  test "JSON encodes recordings with Phoenix.HTML.Form structs" do
    rec = recording_with_form()
    assert {:ok, encoded} = Serializer.encode(rec, :json)
    assert {:ok, _} = Jason.decode(encoded)
  end

  test "JSON output is valid JSON" do
    rec = sample_recording()
    {:ok, encoded} = Serializer.encode(rec, :json)
    assert {:ok, _} = Jason.decode(encoded)
  end

  test "ETF extension is .etf" do
    assert Serializer.extension(:etf) == ".etf"
  end

  test "JSON extension is .json" do
    assert Serializer.extension(:json) == ".json"
  end
end
