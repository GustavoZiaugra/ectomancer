defmodule EctomancerTest do
  use ExUnit.Case
  doctest Ectomancer

  test "returns version" do
    assert Ectomancer.version() == "1.0.0"
  end
end
