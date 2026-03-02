import Config

# config/runtime.exs is executed for all environments, including
# during releases. It is executed after compilation and before the
# system starts, so it is typically used to load production configuration
# and secrets from environment variables or elsewhere. Do not define
# any compile-time configuration in here, as it won't be applied.
# The block below contains prod specific runtime configuration.

# ## Using releases
#
# If you use `mix release`, you need to explicitly enable the server
# by passing the PHX_SERVER=true when you start it:
#
#     PHX_SERVER=true bin/apothecary start
#
# Alternatively, you can use `mix phx.gen.release` to generate a `bin/server`
# script that automatically sets the env var above.
port = String.to_integer(System.get_env("PORT", "4000"))

if System.get_env("PHX_SERVER") || config_env() == :prod do
  config :apothecary, ApothecaryWeb.Endpoint, server: true
end

config :apothecary, ApothecaryWeb.Endpoint, http: [port: port]

# Apothecary project configuration
merge_mode =
  case System.get_env("APOTHECARY_MERGE_MODE") do
    "github" -> :github
    "local" -> :local
    _ -> :auto
  end

config :apothecary,
  port: port,
  project_dir: System.get_env("APOTHECARY_PROJECT_DIR") || File.cwd!(),
  poll_interval: String.to_integer(System.get_env("APOTHECARY_POLL_INTERVAL", "2000")),
  bd_path: System.get_env("APOTHECARY_BD_PATH", "bd"),
  claude_path: System.get_env("APOTHECARY_CLAUDE_PATH", "claude"),
  merge_mode: merge_mode

if config_env() == :prod do
  # Generate a default SECRET_KEY_BASE for local-tool use.
  # Apothecary is a local dev tool, not a public-facing server,
  # so a random key is acceptable when one isn't provided.
  secret_key_base =
    System.get_env("SECRET_KEY_BASE") ||
      :crypto.strong_rand_bytes(64) |> Base.encode64() |> binary_part(0, 64)

  host = System.get_env("PHX_HOST") || "localhost"

  config :apothecary, :dns_cluster_query, System.get_env("DNS_CLUSTER_QUERY")

  config :apothecary, ApothecaryWeb.Endpoint,
    url: [host: host, port: port, scheme: "http"],
    http: [
      ip: {0, 0, 0, 0, 0, 0, 0, 0}
    ],
    secret_key_base: secret_key_base
end
