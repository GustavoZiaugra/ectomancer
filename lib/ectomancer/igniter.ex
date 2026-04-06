defmodule Ectomancer.Igniter do
  @moduledoc """
  Igniter installer for Ectomancer dependency.

  This module provides an Igniter installer for the Ectomancer package.
  It can be used by running `mix igniter.install ectomancer` to add the
  dependency to your project.
  """

  @impl true
  @doc """
  Installs the Ectomancer dependency into the project.

  This function is called by Igniter when the user runs `mix igniter.install ectomancer`.
  It outputs a message indicating the installation is in progress.

  ## Parameters

  - `args`: Command line arguments (unused)
  - `options`: Additional options (unused)

  ## Example

      iex> Ectomancer.Igniter.install([], [])
      "Installing Ectomancer...\n"
  """
  def install(_args, _options) do
    IO.puts("Installing Ectomancer...")
  end
end
