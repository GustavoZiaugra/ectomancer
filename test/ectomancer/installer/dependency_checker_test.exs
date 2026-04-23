defmodule Ectomancer.Installer.DependencyCheckerTest do
  use ExUnit.Case, async: true

  alias Ectomancer.Installer.DependencyChecker

  describe "check_required/0" do
    test "returns :ok when all required deps are present" do
      # This test runs in the ectomancer project which has ecto and plug as deps
      assert DependencyChecker.check_required() == :ok
    end
  end

  describe "check_optional/0" do
    test "returns list of found optional deps" do
      optional_deps = DependencyChecker.check_optional()
      # Should at least check that it returns a list
      assert is_list(optional_deps)
    end
  end

  describe "missing_deps_message/1" do
    test "returns formatted message for missing deps" do
      message = DependencyChecker.missing_deps_message([:ecto, :plug])
      assert String.contains?(message, "Missing required dependencies")
      assert String.contains?(message, "  - ecto")
      assert String.contains?(message, "  - plug")
      assert String.contains?(message, "mix.exs")
    end
  end

  describe "dep_exists?/1" do
    test "returns true for existing deps" do
      # Test with ecto which should exist (it's listed as optional in ectomancer's own deps)
      assert DependencyChecker.dep_exists?(:ecto) == true

      # Test with plug which should exist
      assert DependencyChecker.dep_exists?(:plug) == true
    end

    test "returns false for non-existing deps" do
      assert DependencyChecker.dep_exists?(:nonexistent_dep_12345) == false
    end
  end
end
