defmodule PhoenixReplay.Test.EctoStorageCase do
  @moduledoc false
  # The PhoenixReplay.Storage.Ecto tests, shared by one module per database.
  # The using module's setup_all starts its repo, runs
  # PhoenixReplay.Test.EctoMigration and returns `opts: [repo: Repo]`.

  defmacro __using__(_opts) do
    quote do
      alias PhoenixReplay.Storage.Ecto, as: EctoStorage
      alias PhoenixReplay.Test.Fixtures

      setup %{opts: opts} do
        :ok = EctoStorage.clear(opts)
      end

      test "stores the device, viewport and source with the summary", %{opts: opts} do
        recording = Fixtures.counter_recording(id: "phone")

        client =
          Map.merge(recording.client, %{
            viewport: %{width: 390, height: 844, dpr: 3},
            user_agent:
              "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 " <>
                "(KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1",
            landing: %{path: "/", at: 0, params: %{"utm_source" => "hn"}, referrer: nil}
          })

        :ok = EctoStorage.save(%{recording | client: client}, opts)

        assert [
                 %{
                   viewport: %{width: 390, height: 844, dpr: 3},
                   device: "Mobile Safari 18 on iOS",
                   source: "hn"
                 }
               ] =
                 EctoStorage.list(opts)
      end

      test "saves, fetches and lists summaries newest first", %{opts: opts} do
        older = Fixtures.counter_recording(id: "older", connected_at: 1)
        newer = Fixtures.counter_recording(id: "newer", connected_at: 2)

        assert :ok = EctoStorage.save(older, opts)
        assert :ok = EctoStorage.save(newer, opts)
        assert :ok = EctoStorage.save(newer, opts)

        assert EctoStorage.fetch("older", opts) == {:ok, older}
        assert EctoStorage.fetch("missing", opts) == {:error, :not_found}

        assert [
                 %{
                   id: "newer",
                   view: "PhoenixReplay.Test.Live.Counter",
                   event_count: 6,
                   event_names: ["inc"],
                   duration_ms: 2001
                 },
                 %{id: "older"}
               ] = EctoStorage.list(opts)
      end

      test "deletes one or all recordings", %{opts: opts} do
        for id <- ~w(a b), do: EctoStorage.save(Fixtures.counter_recording(id: id), opts)

        assert :ok = EctoStorage.delete("a", opts)
        assert [%{id: "b"}] = EctoStorage.list(opts)
        assert :ok = EctoStorage.clear(opts)
        assert EctoStorage.list(opts) == []
      end

      describe "query/3" do
        alias PhoenixReplay.Recording.Event
        alias PhoenixReplay.Recordings.Filter

        setup %{opts: opts} do
          error = %Event{at: 9, type: :log, data: %{level: :error, message: "x", metadata: %{}}}

          for {id, at, extra} <- [
                {"a", 1, []},
                {"b", 2, [url: "http://x/sale/100%_off!", tab: "t1"]},
                {"c", 3, [view: Other, error: error]},
                {"d", 4, [tab: "t1"]}
              ] do
            recording = Fixtures.counter_recording(id: id, connected_at: at)

            recording = %{
              recording
              | url: extra[:url] || recording.url,
                view: extra[:view] || recording.view,
                events: recording.events ++ List.wrap(extra[:error]),
                client: Map.put(recording.client, :tab, extra[:tab])
            }

            :ok = EctoStorage.save(recording, opts)
          end

          :ok
        end

        defp ids({summaries, total}), do: {Enum.map(summaries, & &1.id), total}

        test "pages the most recent first and counts every match", %{opts: opts} do
          query = &EctoStorage.query(%Filter{}, &1, opts)

          assert ids(query.(now: 10, limit: 2)) == {~w(d c), 4}
          assert ids(query.(now: 10, offset: 2, limit: 2)) == {~w(b a), 4}
          assert ids(query.(now: 10, until: 3, since: 1, limit: 10)) == {~w(c b), 2}
          assert ids(query.(now: 10, limit: 0)) == {[], 4}
        end

        test "checks each criterion in SQL", %{opts: opts} do
          query = &ids(EctoStorage.query(Filter.from_params(&1), [now: 10, limit: 10], opts))

          assert query.(%{"q" => "100%_OFF"}) == {~w(b), 1}
          assert query.(%{"q" => "%"}) == {~w(b), 1}
          assert query.(%{"q" => "off!"}) == {~w(b), 1}
          assert query.(%{"q" => "_"}) == {~w(b), 1}
          assert query.(%{"view" => "Other"}) == {~w(c), 1}
          assert query.(%{"errors" => "1"}) == {~w(c), 1}
          assert query.(%{"tab" => "t1"}) == {~w(d b), 2}
          assert query.(%{"min_events" => "7"}) == {~w(c), 1}
          assert query.(%{"event" => "inc", "tab" => "t1"}) == {~w(d b), 2}
          assert query.(%{"event" => "nothing"}) == {[], 0}
        end

        test "suggests views and event names", %{opts: opts} do
          assert EctoStorage.facets(opts) == %{
                   views: ["Other", "PhoenixReplay.Test.Live.Counter"],
                   event_names: ["inc"]
                 }
        end
      end
    end
  end
end
