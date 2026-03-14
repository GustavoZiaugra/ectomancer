defmodule Ectomancer.ServerTest do
  use ExUnit.Case
  # doctest Ectomancer.Server

  test "server module exists" do
    assert Code.ensure_loaded?(Ectomancer.Server)
  end
end
