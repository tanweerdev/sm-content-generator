# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

config :cgenerator,
  namespace: SMG,
  ecto_repos: [SMG.Repo],
  generators: [timestamp_type: :utc_datetime]

# Configures the endpoint
config :cgenerator, SMGWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [html: SMGWeb.ErrorHTML, json: SMGWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: SMG.PubSub,
  live_view: [signing_salt: "qgYTLqaJ"]

# Configure esbuild (the version is required)
config :esbuild,
  version: "0.25.4",
  cgenerator: [
    args:
      ~w(js/app.js --bundle --target=es2022 --outdir=../priv/static/assets/js --external:/fonts/* --external:/images/* --alias:@=.),
    cd: Path.expand("../assets", __DIR__),
    env: %{"NODE_PATH" => [Path.expand("../deps", __DIR__), Mix.Project.build_path()]}
  ]

# Configure tailwind (the version is required)
config :tailwind,
  version: "4.1.7",
  cgenerator: [
    args: ~w(
      --input=assets/css/app.css
      --output=priv/static/assets/css/app.css
    ),
    cd: Path.expand("..", __DIR__)
  ]

# Configures Elixir's Logger
config :logger, :default_formatter,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

# Configure Ueberauth for OAuth
config :ueberauth, Ueberauth,
  providers: [
    google:
      {Ueberauth.Strategy.Google,
       [
         default_scope: "openid email profile https://www.googleapis.com/auth/calendar.readonly"
       ]},
    facebook:
      {Ueberauth.Strategy.Facebook,
       [
         default_scope: "email,public_profile,publish_to_groups"
       ]}
  ]

config :ueberauth, Ueberauth.Strategy.Google.OAuth,
  client_id: System.get_env("GOOGLE_CLIENT_ID"),
  client_secret: System.get_env("GOOGLE_CLIENT_SECRET"),
  scope: "openid email profile https://www.googleapis.com/auth/calendar.readonly"

config :ueberauth, Ueberauth.Strategy.Facebook.OAuth,
  client_id: System.get_env("FACEBOOK_APP_ID"),
  client_secret: System.get_env("FACEBOOK_APP_SECRET")

# Configure Goth for Google APIs
config :goth,
  json: System.get_env("GOOGLE_SERVICE_ACCOUNT_JSON") || "{}"

# Configure OpenAI
config :openai,
  api_key: System.get_env("OPENAI_API_KEY"),
  organization_key: System.get_env("OPENAI_ORGANIZATION_KEY"),
  http_options: [recv_timeout: 30_000, timeout: 30_000]

# Configure Tesla to suppress deprecation warnings
config :tesla, disable_deprecated_builder_warning: true

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
