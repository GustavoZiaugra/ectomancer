# Load test support files
for file <- File.ls!("test/support") do
  Code.require_file("support/#{file}", __DIR__)
end

# Start the test repo with sandbox pool and enable manual mode
{:ok, _} =
  Ectomancer.TestRepo.start_link(
    database: ":memory:",
    pool: Ecto.Adapters.SQL.Sandbox,
    pool_size: 10,
    log: false
  )

Ecto.Adapters.SQL.Sandbox.mode(Ectomancer.TestRepo, :manual)

ExUnit.start()
