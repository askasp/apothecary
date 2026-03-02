# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

config :apothecary,
  generators: [timestamp_type: :utc_datetime],
  project_dir: nil,
  claude_path: "claude",
  mnesia_copies: :disc_copies,
  # :auto (detect gh CLI), :github (always PR), :local (merge locally)
  merge_mode: :auto

# Configure the endpoint
config :apothecary, ApothecaryWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [html: ApothecaryWeb.ErrorHTML, json: ApothecaryWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: Apothecary.PubSub,
  live_view: [signing_salt: "dcdBAGrw"]

# Configure esbuild (the version is required)
config :esbuild,
  version: "0.25.4",
  apothecary: [
    args:
      ~w(js/app.js --bundle --target=es2022 --outdir=../priv/static/assets/js --external:/fonts/* --external:/images/* --alias:@=.),
    cd: Path.expand("../assets", __DIR__),
    env: %{"NODE_PATH" => [Path.expand("../deps", __DIR__), Mix.Project.build_path()]}
  ]

# Configure tailwind (the version is required)
config :tailwind,
  version: "4.1.12",
  apothecary: [
    args: ~w(
      --input=assets/css/app.css
      --output=priv/static/assets/css/app.css
    ),
    cd: Path.expand("..", __DIR__)
  ]

# Configure Elixir's Logger
config :logger, :default_formatter,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
