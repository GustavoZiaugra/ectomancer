defmodule EctomancerTest do
  use ExUnit.Case
  doctest Ectomancer

  test "greets the world" do
    assert Ectomancer.hello() == :world
  end
end
