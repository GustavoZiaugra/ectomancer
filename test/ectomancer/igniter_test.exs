defmodule Ectomancer.IgniterTest do
  use ExUnit.Case, async: true

  alias Ectomancer.Igniter

  describe "install/2" do
    test "outputs installation message" do
      assert Igniter.install([], %{}) == :ok
    end
  end
end
