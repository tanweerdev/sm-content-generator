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
#     PHX_SERVER=true bin/cgenerator start
#
# Alternatively, you can use `mix phx.gen.release` to generate a `bin/server`
# script that automatically sets the env var above.
if System.get_env("PHX_SERVER") do
  config :cgenerator, SMGWeb.Endpoint, server: true
end

if config_env() == :prod do
  tzdata_dir = "/tmp/tzdata"
  File.mkdir_p!(tzdata_dir)

  config :tzdata, :data_dir, tzdata_dir

  database_url =
    System.get_env("DATABASE_URL") || ""

  maybe_ipv6 = if System.get_env("ECTO_IPV6") in ~w(true 1), do: [:inet6], else: []

  config :cgenerator, SMG.Repo,
    ssl: true,
    url: database_url,
    pool_size: String.to_integer(System.get_env("POOL_SIZE") || "10"),
    # For machines with several cores, consider starting multiple pools of `pool_size`
    # pool_count: 4,
    socket_options: maybe_ipv6

  # The secret key base is used to sign/encrypt cookies and other secrets.
  # A default value is used in config/dev.exs and config/test.exs but you
  # want to use a different value for prod and you most likely don't want
  # to check this value into version control, so we use an environment
  # variable instead.
  secret_key_base =
    System.get_env("SECRET_KEY_BASE") ||
      System.get_env("SECRET_KEY") ||
      "GMAY+CVidwoYfuWd7KK6rDhP4Ozz6yYnZttALKkCW8Lj2YA7oY/IisJmHqe/PMbK"

  host = System.get_env("PHX_HOST") || "sm-content-generator.fly.dev"
  port = String.to_integer(System.get_env("PORT") || "8080")

  config :cgenerator, :dns_cluster_query, System.get_env("DNS_CLUSTER_QUERY")

  config :cgenerator, SMGWeb.Endpoint,
    url: [host: host, scheme: "https", port: 80],
    http: [
      # Bind on all IPv4 interfaces for Fly.io
      ip: {0, 0, 0, 0},
      port: port
    ],
    secret_key_base: secret_key_base,
    server: true

  # ## SSL Support
  #
  # To get SSL working, you will need to add the `https` key
  # to your endpoint configuration:
  #
  #     config :cgenerator, SMGWeb.Endpoint,
  #       https: [
  #         ...,
  #         port: 443,
  #         cipher_suite: :strong,
  #         keyfile: System.get_env("SOME_APP_SSL_KEY_PATH"),
  #         certfile: System.get_env("SOME_APP_SSL_CERT_PATH")
  #       ]
  #
  # The `cipher_suite` is set to `:strong` to support only the
  # latest and more secure SSL ciphers. This means old browsers
  # and clients may not be supported. You can set it to
  # `:compatible` for wider support.
  #
  # `:keyfile` and `:certfile` expect an absolute path to the key
  # and cert in disk or a relative path inside priv, for example
  # "priv/ssl/server.key". For all supported SSL configuration
  # options, see https://hexdocs.pm/plug/Plug.SSL.html#configure/1
  #
  # We also recommend setting `force_ssl` in your config/prod.exs,
  # ensuring no data is ever sent via http, always redirecting to https:
  #
  #     config :cgenerator, SMGWeb.Endpoint,
  #       force_ssl: [hsts: true]
  #
  # Check `Plug.SSL` for all available options in `force_ssl`.

  # Production OAuth redirect URIs
  config :ueberauth, Ueberauth.Strategy.LinkedIn.OAuth,
    client_id: System.get_env("LINKEDIN_CLIENT_ID"),
    client_secret: System.get_env("LINKEDIN_CLIENT_SECRET"),
    redirect_uri: "https://#{host}/auth/linkedin/callback"

  config :ueberauth, Ueberauth.Strategy.Google.OAuth,
    client_id: System.get_env("GOOGLE_CLIENT_ID"),
    client_secret: System.get_env("GOOGLE_CLIENT_SECRET"),
    scope: "openid email profile https://www.googleapis.com/auth/calendar.readonly",
    redirect_uri: "https://#{host}/auth/google/callback",
    prompt: "consent select_account",
    access_type: "offline"
end
