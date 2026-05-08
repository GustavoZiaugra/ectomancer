defmodule Ectomancer.TestRepo do
  @moduledoc false
  use Ecto.Repo,
    otp_app: :ectomancer,
    adapter: Ecto.Adapters.SQLite3
end
