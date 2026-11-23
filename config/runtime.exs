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
#     PHX_SERVER=true bin/subcipher start
#
# Alternatively, you can use `mix phx.gen.release` to generate a `bin/server`
# script that automatically sets the env var above.
if System.get_env("PHX_SERVER") do
  config :subcipher, SubcipherWeb.Endpoint, server: true
end

config :subcipher, SubcipherWeb.Endpoint,
  http: [port: String.to_integer(System.get_env("PORT", "4000"))]

# Email: sent by SMTP when SMTP_HOST is set (MailDev in development, see
# docker-compose.yml), otherwise kept in memory (Swoosh.Adapters.Local).
#
#   SMTP_HOST, SMTP_PORT (default 587, 1025 for MailDev)
#   SMTP_USERNAME, SMTP_PASSWORD (optional)
#   SMTP_TLS: "always", "never" or "if_available" (default)
#   SMTP_SSL: "true" for implicit TLS (port 465)
#   SMTP_TLS_VERIFY: "false" to accept any certificate (self-signed servers)
#   MAIL_FROM: sender address, MAIL_FROM_NAME: sender name
if config_env() != :test do
  config :subcipher, :mail_from, {
    System.get_env("MAIL_FROM_NAME", "Subcipher"),
    System.get_env("MAIL_FROM", "no-reply@subcipher.local")
  }

  if smtp_host = System.get_env("SMTP_HOST") do
    tls =
      case System.get_env("SMTP_TLS", "if_available") do
        "always" -> :always
        "never" -> :never
        _ -> :if_available
      end

    config :subcipher,
           Subcipher.Mailer,
           [
             adapter: Swoosh.Adapters.SMTP,
             relay: smtp_host,
             port: String.to_integer(System.get_env("SMTP_PORT", "587")),
             ssl: System.get_env("SMTP_SSL") == "true",
             tls: tls,
             tls_options:
               if(System.get_env("SMTP_TLS_VERIFY") == "false",
                 do: [verify: :verify_none],
                 else: [
                   verify: :verify_peer,
                   cacerts: :public_key.cacerts_get(),
                   server_name_indication: String.to_charlist(smtp_host),
                   customize_hostname_check: [
                     match_fun: :public_key.pkix_verify_hostname_match_fun(:https)
                   ]
                 ]
               ),
             retries: 1,
             no_mx_lookups: true
           ] ++
             if(username = System.get_env("SMTP_USERNAME"),
               do: [
                 auth: :always,
                 username: username,
                 password: System.get_env("SMTP_PASSWORD", "")
               ],
               else: [auth: :never]
             )
  else
    if config_env() == :prod do
      raise "environment variable SMTP_HOST is missing (needed to send sign-in emails)"
    end
  end
end

if config_env() == :dev do
  # Reload browser tabs when matching files change.
  config :subcipher, SubcipherWeb.Endpoint,
    live_reload: [
      web_console_logger: true,
      patterns: [
        # Static assets, except user uploads
        ~r"priv/static/(?!uploads/).*\.(js|css|png|jpeg|jpg|gif|svg)$"E,
        # Gettext translations
        ~r"priv/gettext/.*\.po$"E,
        # Router, Controllers, LiveViews and LiveComponents
        ~r"lib/subcipher_web/router\.ex$"E,
        ~r"lib/subcipher_web/(controllers|live|components)/.*\.(ex|heex)$"E
      ]
    ]
end

if config_env() == :prod do
  database_url =
    System.get_env("DATABASE_URL") ||
      raise """
      environment variable DATABASE_URL is missing.
      For example: ecto://USER:PASS@HOST/DATABASE
      """

  maybe_ipv6 = if System.get_env("ECTO_IPV6") in ~w(true 1), do: [:inet6], else: []

  config :subcipher, Subcipher.Repo,
    # ssl: true,
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
      raise """
      environment variable SECRET_KEY_BASE is missing.
      You can generate one by calling: mix phx.gen.secret
      """

  host = System.get_env("PHX_HOST") || "example.com"

  config :subcipher, :dns_cluster_query, System.get_env("DNS_CLUSTER_QUERY")

  config :subcipher, SubcipherWeb.Endpoint,
    url: [host: host, port: 443, scheme: "https"],
    http: [
      # Enable IPv6 and bind on all interfaces.
      # Set it to  {0, 0, 0, 0, 0, 0, 0, 1} for local network only access.
      # See the documentation on https://bandit.hexdocs.pm/Bandit.html#t:options/0
      # for details about using IPv6 vs IPv4 and loopback vs public addresses.
      ip: {0, 0, 0, 0, 0, 0, 0, 0}
    ],
    secret_key_base: secret_key_base

  # ## SSL Support
  #
  # To get SSL working, you will need to add the `https` key
  # to your endpoint configuration:
  #
  #     config :subcipher, SubcipherWeb.Endpoint,
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
  # options, see https://plug.hexdocs.pm/Plug.SSL.html#configure/1
  #
  # We also recommend setting `force_ssl` in your config/prod.exs,
  # ensuring no data is ever sent via http, always redirecting to https:
  #
  #     config :subcipher, SubcipherWeb.Endpoint,
  #       force_ssl: [hsts: true]
  #
  # Check `Plug.SSL` for all available options in `force_ssl`.
end
