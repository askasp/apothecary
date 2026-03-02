import Config

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :apothecary, ApothecaryWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "fgpN26lj+XDk5cbhoUCqc5PJ9AiMAXUGDzH8YhvmVRRoBwQpL8Rvc5POKjXMoaz8",
  server: false


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

# Disable startup checks in tests, use ram_copies for Mnesia
config :apothecary,
  project_dir: nil,
  skip_startup: true,
  mnesia_copies: :ram_copies
