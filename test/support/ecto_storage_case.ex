defmodule PhoenixReplay.Test.EctoStorageCase do
  @moduledoc false
  # The PhoenixReplay.Storage.Ecto tests, shared by one module per database:
  # `use PhoenixReplay.Test.EctoStorageCase, repo: Repo`. Each test runs in
  # a sandboxed transaction on a repo PhoenixReplay.Test.Repos started.

  defmacro __using__(opts) do
    repo = Keyword.fetch!(opts, :repo)

    quote do
      alias PhoenixReplay.Recording.Client.Landing
      alias PhoenixReplay.Storage.Ecto, as: EctoStorage
      alias PhoenixReplay.Test.Fixtures

      setup do
        :ok = Ecto.Adapters.SQL.Sandbox.checkout(unquote(repo))
        %{opts: [repo: unquote(repo)]}
      end

      test "stores the device, viewport and source with the summary", %{opts: opts} do
        recording = Fixtures.counter_recording(id: "phone")

        client = %{
          recording.client
          | viewport: %{width: 390, height: 844, dpr: 3},
            user_agent:
              "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 " <>
                "(KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1",
            landing: %Landing{path: "/", at: 0, params: %{"utm_source" => "hn"}}
        }

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
        alias PhoenixReplay.Recording.{Event, Filter}

        setup %{opts: opts} do
          error = %Event{at: 9, type: :log, data: %{level: :error, message: "x", metadata: %{}}}

          mark = %Event{
            at: 9,
            type: :telemetry,
            data: %{event: [:shop, :paid], measurements: %{}, metadata: %{}, mark: "Paid"}
          }

          google = %PhoenixReplay.Recording.Client.Landing{
            path: "/",
            at: 0,
            params: %{"utm_source" => "google", "utm_medium" => "cpc"}
          }

          for {id, at, extra} <- [
                {"a", 1, []},
                {"b", 2,
                 [url: "http://x/sale/100%_off!", tab: "t1", landing: google, mark: mark]},
                {"c", 3,
                 [view: Other, error: error, viewport: %{width: 390, height: 844, dpr: 3}]},
                {"d", 4, [tab: "t1", mark: mark]}
              ] do
            recording = Fixtures.counter_recording(id: id, connected_at: at)

            recording = %{
              recording
              | url: extra[:url] || recording.url,
                view: extra[:view] || recording.view,
                events: recording.events ++ List.wrap(extra[:error]) ++ List.wrap(extra[:mark]),
                client: %{
                  recording.client
                  | tab: extra[:tab],
                    landing: extra[:landing],
                    viewport: extra[:viewport]
                }
            }

            :ok = EctoStorage.save(recording, opts)
          end

          :ok
        end

        defp ids({summaries, total}), do: {Enum.map(summaries, & &1.id), total}

        test "bounds pages by when recordings were saved", %{opts: opts} do
          moment = fn ->
            Process.sleep(2)
            at = System.system_time(:millisecond)
            Process.sleep(2)
            at
          end

          # a to d were saved by setup; e started before them all but ends later.
          saved = moment.()
          :ok = EctoStorage.save(Fixtures.counter_recording(id: "e", connected_at: 0), opts)
          query = &ids(EctoStorage.query(%Filter{}, [now: 10, limit: 10] ++ &1, opts))

          assert query.(until: saved) == {~w(d c b a), 4}
          assert query.(since: saved) == {~w(e), 1}
        end

        test "orders sessions that started together by id, so pages never repeat", %{
          opts: opts
        } do
          for id <- ~w(t1 t2 t3),
              do: EctoStorage.save(Fixtures.counter_recording(id: id, connected_at: 99), opts)

          page = &ids(EctoStorage.query(%Filter{}, [now: 100, offset: &1, limit: 1], opts))

          assert Enum.map(0..2, &page.(&1)) == [{~w(t3), 7}, {~w(t2), 7}, {~w(t1), 7}]
        end

        test "pages the most recent first and counts every match", %{opts: opts} do
          query = &EctoStorage.query(%Filter{}, &1, opts)

          assert ids(query.(now: 10, limit: 2)) == {~w(d c), 4}
          assert ids(query.(now: 10, offset: 2, limit: 2)) == {~w(b a), 4}
          assert ids(query.(now: 10, limit: 0)) == {[], 4}
        end

        test "checks each criterion in SQL", %{opts: opts} do
          query = &ids(EctoStorage.query(Filter.from_params(&1), [now: 10, limit: 10], opts))

          assert query.(%{"q" => "100%_OFF"}) == {~w(b), 1}
          assert query.(%{"q" => "%"}) == {~w(b), 1}
          assert query.(%{"q" => "off!"}) == {~w(b), 1}
          assert query.(%{"q" => "_"}) == {~w(b), 1}
          assert query.(%{"q" => "INC"}) == {~w(d c b a), 4}
          assert query.(%{"view" => "Other"}) == {~w(c), 1}
          assert query.(%{"errors" => "1"}) == {~w(c), 1}
          assert query.(%{"tab" => "t1"}) == {~w(d b), 2}
          assert query.(%{"min_events" => "7"}) == {~w(d c b), 3}
          assert query.(%{"min_events" => "8"}) == {[], 0}
          assert query.(%{"event" => "inc", "tab" => "t1"}) == {~w(d b), 2}
          assert query.(%{"event" => "nothing"}) == {[], 0}
          assert query.(%{"mark" => "Paid"}) == {~w(d b), 2}
          assert query.(%{"mark" => "Paid", "q" => "sale"}) == {~w(b), 1}
          assert query.(%{"source" => "google", "medium" => "cpc"}) == {~w(b), 1}
          assert query.(%{"device_type" => "phone"}) == {~w(c), 1}
          assert query.(%{"longer_than" => "2"}) == {~w(d c b a), 4}
          assert query.(%{"longer_than" => "3"}) == {[], 0}

          # Marks come with the summaries, from their own table.
          assert {[%{id: "d", marks: %{"Paid" => 1}} | _rest], 2} =
                   EctoStorage.query(
                     Filter.from_params(%{"mark" => "Paid"}),
                     [now: 10, limit: 10],
                     opts
                   )
        end

        test "counts the values of views and event names", %{opts: opts} do
          values = &EctoStorage.values(&1, Filter.from_params(&2), [now: 10, limit: 10], opts)

          assert values.(:view, %{}) == [{"PhoenixReplay.Test.Live.Counter", 3}, {"Other", 1}]
          # A field's own criterion leaves its other values on offer.
          assert values.(:view, %{"view" => "Other"}) == values.(:view, %{})
          assert values.(:view, %{"errors" => "1"}) == [{"Other", 1}]

          assert values.(:view, %{"event" => "inc", "tab" => "t1"}) == [
                   {"PhoenixReplay.Test.Live.Counter", 2}
                 ]

          assert values.(:event, %{"tab" => "t1"}) == [{"inc", 2}]
          assert values.(:mark, %{}) == [{"Paid", 2}]
          assert values.(:mark, %{"q" => "sale"}) == [{"Paid", 1}]
          assert values.(:source, %{}) == [{"google", 1}]
          assert values.(:device_type, %{"mark" => "Paid"}) == []
          assert values.(:device_type, %{}) == [{"phone", 1}]
        end
      end
    end
  end
end
