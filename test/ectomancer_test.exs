defmodule EctomancerTest do
  use ExUnit.Case
  doctest Ectomancer

  test "returns version" do
    assert Ectomancer.version() == "0.1.0"
  end
end
