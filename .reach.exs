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
  "PhoenixReplay.Export",
  "PhoenixReplay.Trace",
  "PhoenixReplay.Plug",
  "PhoenixReplay.Recorder",
  "PhoenixReplay.Router",
  "PhoenixReplay.Web.*"
]

# Session modules follow a recording until it is stored; its buffer is
# infrastructure that capture writes to.
orchestrator = [
  "PhoenixReplay.Catalog",
  "PhoenixReplay.Storage.Retention",
  "PhoenixReplay.Session.Finalizer",
  "PhoenixReplay.Session.Flusher",
  "PhoenixReplay.Session.Monitor",
  "PhoenixReplay.Session.Recovery",
  # Video export: the queue and the render of one video.
  "PhoenixReplay.Export.Queue",
  "PhoenixReplay.Export.Queue.Local",
  "PhoenixReplay.Export.Supervisor",
  "PhoenixReplay.Export.Video"
]

model = [
  "PhoenixReplay.Config",
  "PhoenixReplay.Export.Job",
  "PhoenixReplay.Export.Options",
  "PhoenixReplay.Export.Schedule",
  "PhoenixReplay.Recording",
  "PhoenixReplay.Recording.*"
]

# Behaviours and their built-in implementations.
logic = [
  "PhoenixReplay.Authorization",
  "PhoenixReplay.Replayable",
  "PhoenixReplay.Collector*",
  "PhoenixReplay.Redactor*",
  "PhoenixReplay.Sanitizer*",
  "PhoenixReplay.Session.TailSampling",
  "PhoenixReplay.Storage.Codec"
]

infrastructure = [
  "PhoenixReplay.Application",
  "PhoenixReplay.Capture.*",
  # Video export's outside processes: the endpoint and Chromium, and ffmpeg.
  "PhoenixReplay.Export.Encoder",
  "PhoenixReplay.Export.FFmpeg",
  "PhoenixReplay.Export.FFmpeg.Output",
  "PhoenixReplay.Export.Runtime",
  "PhoenixReplay.Export.Screenshots",
  "PhoenixReplay.Session.Buffer",
  "PhoenixReplay.Storage",
  "PhoenixReplay.Storage.Ecto",
  "PhoenixReplay.Storage.Ecto.Migration",
  "PhoenixReplay.Storage.File",
  "PhoenixReplay.Storage.File.Index",
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
      {"PhoenixReplay.Sanitizer*", ["File.*", ":ets.*", "Phoenix.PubSub.*"]},
      {"PhoenixReplay.Redactor*", ["File.*", ":ets.*", "Phoenix.PubSub.*"]}
    ]
  ],
  smells: [strict: true]
]
