import Config

# Only in tests, remove the complexity from the password hashing algorithm
config :bcrypt_elixir, :log_rounds, 1

# Configure your database
#
# The MIX_TEST_PARTITION environment variable can be used
# to provide built-in test partitioning in CI environment.
# Run `mix help test` for more information.
config :subcipher, Subcipher.Repo,
  username: "postgres",
  password: "postgres",
  hostname: "localhost",
  port: String.to_integer(System.get_env("POSTGRES_PORT", "5432")),
  database: "subcipher_test#{System.get_env("MIX_TEST_PARTITION")}",
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: System.schedulers_online() * 2

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :subcipher, SubcipherWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "Xk5DlaElI7zvtMLVieklwQUSu2PmE+zgN95rgrOHISnyjH6jwTwhRhXMkIMxfSoG",
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

# Uploaded cipher pictures
config :subcipher, :uploads_dir, Path.join(System.tmp_dir!(), "subcipher_test_uploads")

# Emails are collected in the test process (Swoosh.TestAssertions).
config :subcipher, Subcipher.Mailer, adapter: Swoosh.Adapters.Test

# Tests run many guesses at once: don't turn deep guesses away as busy.
config :subcipher, Subcipher.Guesser.Limiter, max: 1000
