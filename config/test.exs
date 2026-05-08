import Config

# Suppress Ecto query debug logs in test output
config :ectomancer, Ectomancer.TestRepo,
  database: ":memory:",
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: 10,
  log: false
