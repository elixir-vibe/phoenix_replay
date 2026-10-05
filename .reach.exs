app_config = [
  "Application.get_env",
  "Application.get_all_env",
  "Application.fetch_env",
  "Application.fetch_env!",
  "Application.put_env",
  "Application.delete_env"
]

# Video export drives a browser through its own endpoint, so most of it
# is an adapter; its plan and jobs are data, and ffmpeg is infrastructure.
adapter = [
  "Mix.Tasks.PhoenixReplay.*",
  "PhoenixReplay",
  "PhoenixReplay.Export",
  "PhoenixReplay.Export.Access",
  "PhoenixReplay.Export.Capture",
  "PhoenixReplay.Export.Endpoint",
  "PhoenixReplay.Export.ErrorHTML",
  "PhoenixReplay.Export.Router",
  "PhoenixReplay.Export.Runtime",
  "PhoenixReplay.Export.Server",
  "PhoenixReplay.Export.Stage",
  "PhoenixReplay.Export.Supervisor",
  "PhoenixReplay.Export.Video",
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
  "PhoenixReplay.Session.Recovery"
]

model = [
  "PhoenixReplay.Config",
  "PhoenixReplay.Export.Job",
  "PhoenixReplay.Export.Schedule",
  "PhoenixReplay.Recording",
  "PhoenixReplay.Recording.*"
]

# Behaviours and their built-in implementations.
logic = [
  "PhoenixReplay.Authorization",
  "PhoenixReplay.Collector*",
  "PhoenixReplay.Redactor*",
  "PhoenixReplay.Sanitizer*",
  "PhoenixReplay.Session.TailSampling",
  "PhoenixReplay.Storage.Codec"
]

infrastructure = [
  "PhoenixReplay.Application",
  "PhoenixReplay.Capture.*",
  "PhoenixReplay.Export.Encoder",
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
