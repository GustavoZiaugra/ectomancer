defmodule Ectomancer.Tool.DSLTest do
  use ExUnit.Case, async: true

  describe "DSL macros" do
    test "macros compile and return nil" do
      defmodule DSLTestUser do
        import Ectomancer.Tool.DSL

        def get_desc, do: description("a simple tool")
        def get_param, do: param(:field, :string, required: true)
        def get_handle, do: handle(do: :ok)
      end

      assert DSLTestUser.get_desc() == nil
      assert DSLTestUser.get_param() == nil
      assert DSLTestUser.get_handle() == nil
    end
  end
end
