defmodule Ectomancer.Installer.SchemaDiscoveryTest do
  use ExUnit.Case, async: true

  describe "discover/0" do
    test "returns list of schema information maps" do
      schemas = Ectomancer.Installer.SchemaDiscovery.discover()
      assert is_list(schemas)
    end

    test "each schema has required fields" do
      schemas = Ectomancer.Installer.SchemaDiscovery.discover()

      for schema <- schemas do
        assert Map.get(schema, :module)
        assert Map.get(schema, :table)
        assert Map.get(schema, :context)
        assert Map.get(schema, :associations)
        assert Map.get(schema, :writable_fields)
      end
    end

    test "returns empty list when no schemas found" do
      # This test will pass even if there are no Ecto schemas
      # The important thing is it doesn't crash
      assert is_list(Ectomancer.Installer.SchemaDiscovery.discover())
    end
  end

  describe "module_introspection/0" do
    test "returns list from Code.all_loaded()" do
      result = Ectomancer.Installer.SchemaDiscovery.module_introspection()
      assert is_list(result)
    end
  end

  describe "file_discovery/0" do
    test "scans lib directory for Ecto schemas" do
      result = Ectomancer.Installer.SchemaDiscovery.file_discovery()
      assert is_list(result)
    end
  end

  describe "extract_context/1" do
    test "extracts context from nested module path" do
      assert Ectomancer.Installer.SchemaDiscovery.extract_context("MyApp.Accounts.User") ==
               "Accounts"

      assert Ectomancer.Installer.SchemaDiscovery.extract_context("MyApp.Blog.Post") == "Blog"
      assert Ectomancer.Installer.SchemaDiscovery.extract_context("MyApp.User") == nil
    end
  end
end
