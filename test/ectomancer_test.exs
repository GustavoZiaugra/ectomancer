defmodule EctomancerTest do
  use ExUnit.Case
  doctest Ectomancer

  test "returns version" do
    assert Ectomancer.version() == Application.spec(:ectomancer, :vsn) |> to_string()
  end
end
