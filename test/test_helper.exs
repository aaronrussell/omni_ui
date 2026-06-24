sessions_dir = Path.expand("tmp/test_sessions", __DIR__)

Application.put_env(:omni_ui, Omni.UI.TestEndpoint,
  http: [ip: {127, 0, 0, 1}, port: 4099],
  secret_key_base: String.duplicate("a", 64),
  server: false,
  live_view: [signing_salt: "test_signing"],
  render_errors: [formats: [html: Omni.UI.TestErrorHTML], layout: false]
)

Application.put_env(:omni_ui, Omni.UI.Sessions,
  sessions_base_dir: sessions_dir,
  store: {Omni.Session.Stores.FileSystem, base_dir: sessions_dir},
  title_generator: false
)

Application.put_env(:omni, Omni.Providers.Ollama, models: ["gemma4:latest"])
Omni.Provider.load([:ollama])

Application.put_env(:omni_ui, Omni.UI.AgentLive,
  providers: [:ollama],
  default_model: {:ollama, "gemma4:latest"}
)

{:ok, _} = Omni.UI.TestEndpoint.start_link()
{:ok, _} = Omni.UI.Sessions.start_link([])

Logger.configure(level: :warning)

ExUnit.start(exclude: [:wip])
