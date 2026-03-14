defmodule Ectomancer.ToolTest do
  use ExUnit.Case
  # doctest Ectomancer.Tool

  test "tool module exists" do
    assert Code.ensure_loaded?(Ectomancer.Tool)
  end
end
