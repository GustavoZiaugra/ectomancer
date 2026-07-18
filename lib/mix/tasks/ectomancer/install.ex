defmodule Mix.Tasks.Ectomancer.Install do
  @moduledoc """
  Igniter installer for Ectomancer.

  This Mix task is automatically discovered and run by `mix igniter.install ectomancer`.
  It configures Ectomancer in the user's project after the dependency is added.

  ## Usage

      mix igniter.install ectomancer

  This will:
  1. Check for required dependencies (Ecto, Plug)
  2. Discover Ecto schemas in your project
  3. Prompt you to select which schemas to expose
  4. Generate an MCP module exposing the selected schemas
  5. Configure Ectomancer in `config/config.exs`
  6. Add the MCP route to your Phoenix router
  7. Add the Anubis supervisor to your application supervision tree
  """

  use Igniter.Mix.Task

  @impl Igniter.Mix.Task
  def igniter(igniter) do
    Ectomancer.Igniter.install(igniter, [])
  end
end
