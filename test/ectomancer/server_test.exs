defmodule Ectomancer.ServerTest do
  use ExUnit.Case

  alias Ectomancer.Server

  describe "get_actor/1" do
    test "returns actor from frame assigns" do
      actor = %{id: 1, name: "Test User"}
      frame = %{assigns: %{ectomancer_actor: actor}}

      assert Server.get_actor(frame) == actor
    end

    test "returns nil when actor not in assigns" do
      frame = %{assigns: %{}}

      assert Server.get_actor(frame) == nil
    end

    test "returns nil when assigns is empty" do
      frame = %{assigns: %{}}

      assert Server.get_actor(frame) == nil
    end
  end
end
