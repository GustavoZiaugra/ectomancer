defmodule Ectomancer.Igniter do
  @moduledoc """
  Igniter installer for Ectomancer dependency.

  This module provides an Igniter installer for the Ectomancer package.
  It can be used by running `mix igniter.install ectomancer` to add the
  dependency to your project.
  """

  def install(_args, _options) do
    IO.puts("Installing Ectomancer...")
  end
end
