defmodule PhoenixReplay.Test.ObanQueueCase do
  @moduledoc """
  The `PhoenixReplay.Export.Queue.Oban` tests, shared by one module per
  database: `use PhoenixReplay.Test.ObanQueueCase, repo: Repo, engine:
  Engine`. The tests use the Oban instance `PhoenixReplay.Test.Repos`
  started on the repo, in Oban's `testing: :manual` mode where the engine
  supports it, so jobs wait until a test drains the queue, and assert on
  them with `Oban.Testing`.

  Tests run in a sandboxed transaction, except with `sandbox: false`, for
  DuckDB, which cannot open the transactions Oban's engine does inside
  the sandbox's; its jobs are deleted before each test instead.
  """

  defmacro __using__(opts) do
    repo = Keyword.fetch!(opts, :repo)
    sandbox? = Keyword.get(opts, :sandbox, true)

    quote do
      import Ecto.Query, only: [from: 2]

      use Oban.Testing, repo: unquote(repo), prefix: false

      alias PhoenixReplay.Export
      alias PhoenixReplay.Export.{Job, Options}
      alias PhoenixReplay.Export.Queue.Oban, as: Queue

      @oban PhoenixReplay.Test.Repos.oban(unquote(repo))

      setup do
        if unquote(sandbox?) do
          :ok = Ecto.Adapters.SQL.Sandbox.checkout(unquote(repo))
        else
          :ok = Ecto.Adapters.SQL.Sandbox.checkout(unquote(repo), sandbox: false)
          unquote(repo).delete_all(Oban.Job)
        end

        config = PhoenixReplay.Config.load()
        %{opts: [oban: @oban, queue: :replay_exports], config: config}
      end

      defp options(config), do: %{Options.new(config.export) | from: 2_000, size: :half}

      # Moves the job of `id` as Oban would.
      defp put_job(id, changes) do
        "oban-" <> number = id
        query = from(j in Oban.Job, where: j.id == ^String.to_integer(number))
        unquote(repo).update_all(query, set: changes)
      end

      test "queues an export once per recording, and finds it", %{opts: opts, config: config} do
        :ok = Export.subscribe("rec")

        assert {:ok, %Job{id: "oban-" <> _, status: :queued, recording_id: "rec"} = job} =
                 Queue.start("rec", config, options(config), opts)

        assert_receive {Export, %Job{id: id, status: :queued}} when id == job.id

        assert_enqueued(
          worker: Queue.Worker,
          queue: :replay_exports,
          args: %{"recording_id" => "rec"},
          meta: %{"timeout" => :timer.hours(1)}
        )

        # Asked again while it waits, the same export comes back, unannounced.
        assert {:ok, %Job{id: same}} =
                 Queue.start("rec", config, Options.new(config.export), opts)

        assert same == job.id
        refute_receive {Export, _job}

        assert %Job{options: %Options{from: 2_000, size: :half}} = Queue.get(job.id, opts)
        assert Queue.latest("rec", opts).id == job.id
        assert Queue.latest("other", opts) == nil
        assert Queue.get("oban-0", opts) == nil
        assert Queue.get(String.replace(job.id, "oban-", "oban-0"), opts) == nil
        assert Queue.get("not-oban", opts) == nil
      end

      test "keeps one export of a recording however long it waits", %{opts: opts, config: config} do
        {:ok, job} = Queue.start("rec", config, options(config), opts)
        # Older than Oban's default uniqueness period of a minute.
        put_job(job.id, inserted_at: DateTime.add(DateTime.utc_now(), -3_600, :second))

        assert {:ok, %Job{id: same}} = Queue.start("rec", config, options(config), opts)
        assert same == job.id
      end

      test "gives an export the time its queue allows", %{opts: opts, config: config} do
        {:ok, job} =
          Queue.start("rec", config, options(config), Keyword.put(opts, :timeout, 5_000))

        "oban-" <> number = job.id
        oban_job = unquote(repo).get!(Oban.Job, String.to_integer(number))

        # Oban kills the job only a minute after the worker stops it itself.
        assert Queue.Worker.timeout(oban_job) == 5_000 + :timer.minutes(1)
      end

      test "cancels a running export no node runs any more", %{opts: opts, config: config} do
        {:ok, job} = Queue.start("rec", config, options(config), opts)
        # As a deploy leaves it: executing, with nothing rendering it.
        put_job(job.id, state: "executing")

        assert :ok = Queue.cancel(job.id, opts)
        assert %Job{status: :cancelled} = Queue.get(job.id, opts)
      end

      test "cancels a queued export", %{opts: opts, config: config} do
        {:ok, job} = Queue.start("rec", config, options(config), opts)
        :ok = Export.subscribe("rec")

        assert :ok = Queue.cancel(job.id, opts)
        assert_receive {Export, %Job{status: :cancelled}}
        assert %Job{status: :cancelled} = Queue.get(job.id, opts)

        # Once cancelled, another export of the recording can start.
        assert {:ok, %Job{id: other}} = Queue.start("rec", config, options(config), opts)
        assert other != job.id
      end

      test "reads progress, the video and errors from the job", %{opts: opts, config: config} do
        {:ok, job} = Queue.start("rec", config, options(config), opts)

        put_job(job.id, state: "executing", meta: %{"progress" => 40, "node" => "nonode@nohost"})

        assert %Job{status: :running, progress: 40, node: :nonode@nohost} =
                 Queue.get(job.id, opts)

        put_job(job.id,
          state: "completed",
          completed_at: DateTime.utc_now(),
          meta: %{"path" => "/tmp/v.mp4", "node" => "unknown_node@nowhere"}
        )

        # A node this one never heard of cannot serve the video.
        assert %Job{status: :done, progress: 100, path: "/tmp/v.mp4", node: nil} =
                 Queue.get(job.id, opts)

        put_job(job.id,
          state: "discarded",
          completed_at: nil,
          discarded_at: DateTime.utc_now(),
          meta: %{"error" => "ffmpeg failed."}
        )

        assert %Job{status: :failed, error: "ffmpeg failed."} = Queue.get(job.id, opts)
      end

      test "stops listing an export once its video is gone", %{opts: opts, config: config} do
        {:ok, job} = Queue.start("rec", config, options(config), opts)
        old = DateTime.add(DateTime.utc_now(), -config.export.ttl - 1_000, :millisecond)
        put_job(job.id, state: "completed", completed_at: old)

        assert Queue.get(job.id, opts) == nil
        assert Queue.latest("rec", opts) == nil
      end

      describe "rendering" do
        # Real exports: Chromium films the replay and ffmpeg encodes it.
        @describetag :export
        @describetag timeout: 120_000

        alias PhoenixReplay.Storage
        alias PhoenixReplay.Test.Fixtures

        setup do
          recording =
            Fixtures.counter_recording(
              id: "oban-#{System.unique_integer([:positive])}",
              clicks: 10
            )

          :ok = Storage.save(Fixtures.storage(), recording)
          on_exit(fn -> Storage.delete(Fixtures.storage(), recording.id) end)
          :ok = Export.subscribe(recording.id)
          %{recording: recording}
        end

        # Runs the queue's jobs in the test process, as a node taking them
        # would; Oban's way of running jobs in tests.
        defp drain, do: Oban.drain_queue(@oban, queue: :replay_exports)

        test "renders the video and keeps where it is", %{
          recording: recording,
          opts: opts,
          config: config
        } do
          {:ok, job} = Queue.start(recording.id, config, Options.new(config.export), opts)
          assert %{success: 1} = drain()

          assert %Job{status: :done, progress: 100, path: path, node: node} =
                   Queue.get(job.id, opts)

          assert node == node()
          assert File.exists?(path)
          assert Path.basename(path) == job.id <> ".mp4"
          assert_received {Export, %Job{status: :running}}
          assert_received {Export, %Job{status: :done}}
        end

        test "fails an export that runs past its time, closing what it opened",
             %{recording: recording, opts: opts, config: config} do
          {:ok, job} =
            Queue.start(
              recording.id,
              config,
              Options.new(config.export),
              Keyword.put(opts, :timeout, 1)
            )

          drain()

          assert %Job{status: :failed, error: "The export took longer than" <> _} =
                   Queue.get(job.id, opts)

          dir = Export.Video.dir(config.export)
          refute File.exists?(Path.join(dir, job.id))
          refute File.exists?(Path.join(dir, job.id <> ".mp4"))
        end

        test "stops a running export where it runs", %{
          recording: recording,
          opts: opts,
          config: config
        } do
          {:ok, job} = Queue.start(recording.id, config, Options.new(config.export), opts)
          rendering = Task.async(&drain/0)

          # Once it has screenshots to throw away.
          assert_receive {Export, %Job{status: :running, progress: progress}} when progress > 0,
                         30_000

          :ok = Queue.cancel(job.id, opts)
          assert_receive {Export, %Job{status: :cancelling}}

          assert %{cancelled: 1} = Task.await(rendering, 60_000)
          assert %Job{status: :cancelled, path: nil} = Queue.get(job.id, opts)

          dir = Export.Video.dir(config.export)
          refute File.exists?(Path.join(dir, job.id))
          refute File.exists?(Path.join(dir, job.id <> ".mp4"))
        end
      end
    end
  end
end
