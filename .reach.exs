app_config = [
  "Application.get_env",
  "Application.get_all_env",
  "Application.fetch_env",
  "Application.fetch_env!",
  "Application.put_env",
  "Application.delete_env"
]

adapter = [
  "Mix.Tasks.PhoenixReplay.*",
  "PhoenixReplay",
  "PhoenixReplay.Recorder",
  "PhoenixReplay.Router",
  "PhoenixReplay.Web.*"
]

orchestrator = [
  "PhoenixReplay.Recordings",
  "PhoenixReplay.Retention",
  "PhoenixReplay.Recorder.Monitor",
  "PhoenixReplay.Recorder.Persister"
]

model = [
  "PhoenixReplay.Config",
  "PhoenixReplay.Recording",
  "PhoenixReplay.Recording.Event",
  "PhoenixReplay.Recording.Summary",
  "PhoenixReplay.Recording.Timeline",
  "PhoenixReplay.Recordings.Filter"
]

logic = [
  "PhoenixReplay.Authorization",
  "PhoenixReplay.Sanitizer",
  "PhoenixReplay.Sanitizer.Default",
  "PhoenixReplay.Storage.Codec"
]

infrastructure = [
  "PhoenixReplay.Application",
  "PhoenixReplay.Recorder.Buffer",
  "PhoenixReplay.Recorder.Components",
  "PhoenixReplay.Storage",
  "PhoenixReplay.Storage.Ecto",
  "PhoenixReplay.Storage.File",
  "PhoenixReplay.Telemetry"
]

[
  layers: [
    adapter: adapter,
    orchestrator: orchestrator,
    model: model,
    logic: logic,
    infrastructure: infrastructure
  ],
  checks: [
    layer_coverage: [
      require_all_modules: true,
      forbid_multiple_matches: true,
      # Reach also discovers example/lib; the example app is not part of the library.
      ignore: [
        "PhoenixReplay.Test.*",
        "Example",
        "Example.*",
        "ExampleWeb",
        "ExampleWeb.*",
        "Reach.Templates.*"
      ]
    ]
  ],
  deps: [
    forbidden: [
      {:model, :adapter},
      {:model, :orchestrator},
      {:model, :infrastructure},
      {:logic, :adapter},
      {:logic, :orchestrator},
      {:logic, :infrastructure},
      {:infrastructure, :adapter},
      {:infrastructure, :orchestrator},
      {:orchestrator, :adapter}
    ]
  ],
  calls: [
    forbidden: [
      {"PhoenixReplay*", app_config, except: ["PhoenixReplay.Config"]},
      {"PhoenixReplay.Recording", ["File.*", ":ets.*", "Phoenix.PubSub.*"]},
      {"PhoenixReplay.Recording.*", ["File.*", ":ets.*", "Phoenix.PubSub.*"]},
      {"PhoenixReplay.Sanitizer*", ["File.*", ":ets.*", "Phoenix.PubSub.*"]}
    ]
  ],
  smells: [strict: true]
]
