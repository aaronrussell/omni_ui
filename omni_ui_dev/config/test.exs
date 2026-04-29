import Config

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :omni_ui_dev, OmniUIDevWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "YEYVl1pLygKbsbrboNKMI1BKoRqcamuva8dA+ZmgwlTQa4772Qyu022WQzQpsC3v",
  server: false

# Isolate the test sessions store from dev/prod data.
config :omni_ui, OmniUI.Sessions,
  store: {Omni.Session.Store.FileSystem, base_path: "tmp/test_sessions", otp_app: :omni_ui_dev}

# Print only warnings and errors during test
config :logger, level: :warning

# Initialize plugs at runtime for faster test compilation
config :phoenix, :plug_init_mode, :runtime

# Enable helpful, but potentially expensive runtime checks
config :phoenix_live_view,
  enable_expensive_runtime_checks: true

# Sort query params output of verified routes for robust url comparisons
config :phoenix,
  sort_verified_routes_query_params: true
