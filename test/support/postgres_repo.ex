defmodule Ectomancer.PostgresRepo do
  @moduledoc """
  Repo used by the Postgres-only integration tests.

  Started from `test_helper.exs` only when `ECTOMANCER_PG_URL` is set, e.g.:

      ECTOMANCER_PG_URL=postgres://postgres:postgres@localhost:5432/ectomancer_test \\
        mix test --only postgres
  """

  use Ecto.Repo,
    otp_app: :ectomancer,
    adapter: Ecto.Adapters.Postgres
end
