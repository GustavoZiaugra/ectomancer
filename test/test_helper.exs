# Start the test repo with sandbox pool and enable manual mode
{:ok, _} =
  Ectomancer.TestRepo.start_link(
    database: ":memory:",
    pool: Ecto.Adapters.SQL.Sandbox,
    pool_size: 10,
    log: false
  )

Ecto.Adapters.SQL.Sandbox.mode(Ectomancer.TestRepo, :manual)

# Postgres-only integration tests run only when ECTOMANCER_PG_URL is set
# (see test/ectomancer/postgres_scope_test.exs and the CI postgres job).
if pg_url = System.get_env("ECTOMANCER_PG_URL") do
  {:ok, _} =
    Ectomancer.PostgresRepo.start_link(
      url: pg_url,
      pool: Ecto.Adapters.SQL.Sandbox,
      pool_size: 5,
      log: false
    )

  Ecto.Adapters.SQL.Sandbox.mode(Ectomancer.PostgresRepo, :manual)
else
  ExUnit.configure(exclude: [:postgres])
end

ExUnit.start()
