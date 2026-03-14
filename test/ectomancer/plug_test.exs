defmodule Ectomancer.PlugTest do
  use ExUnit.Case
  # doctest Ectomancer.Plug

  test "plug module exists" do
    assert Code.ensure_loaded?(Ectomancer.Plug)
  end
end
