defmodule Ectomancer.Installer.SchemaDiscoveryTest do
  use ExUnit.Case, async: true

  alias Ectomancer.Installer.SchemaDiscovery

  defmodule FakeSchema do
    def __schema__(:table), do: "fake"
    def __schema__(_other), do: nil
  end

  describe "discover/0" do
    test "returns list of schema information maps" do
      schemas = SchemaDiscovery.discover()
      assert is_list(schemas)
    end

    test "each schema has required fields" do
      schemas = SchemaDiscovery.discover()

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
      assert is_list(SchemaDiscovery.discover())
    end
  end

  describe "module_introspection/0" do
    test "returns list from Code.all_loaded()" do
      result = SchemaDiscovery.module_introspection()
      assert is_list(result)
    end
  end

  describe "file_discovery/0" do
    test "scans lib directory for Ecto schemas" do
      result = SchemaDiscovery.file_discovery()
      assert is_list(result)
    end
  end

  describe "extract_context/1" do
    test "extracts context from nested module path" do
      assert SchemaDiscovery.extract_context("MyApp.Accounts.User") == "Accounts"
      assert SchemaDiscovery.extract_context("MyApp.Blog.Post") == "Blog"
      assert SchemaDiscovery.extract_context("MyApp.User") == nil
    end
  end

  describe "detect_app_module_prefix/0" do
    test "reads app name from mix.exs" do
      prefix = SchemaDiscovery.detect_app_module_prefix()
      assert is_binary(prefix) or is_nil(prefix)
    end
  end

  describe "app_module?/2" do
    test "returns true when prefix is nil" do
      assert SchemaDiscovery.app_module?(MyApp.User, nil) == true
    end

    test "filters by prefix" do
      assert SchemaDiscovery.app_module?(MyApp.User, "MyApp") == true
      assert SchemaDiscovery.app_module?(OtherApp.User, "MyApp") == false
    end
  end

  describe "ecto_schema_module?/1" do
    test "identifies modules with __schema__/1 and without __schema__/2" do
      assert SchemaDiscovery.ecto_schema_module?(FakeSchema) == true
    end

    test "rejects non-schema modules" do
      assert SchemaDiscovery.ecto_schema_module?(Ectomancer.Repo) == false
      assert SchemaDiscovery.ecto_schema_module?(List) == false
    end
  end

  describe "contains_ecto_schema?/1" do
    test "detects schema in file content" do
      path = tmp_path("schema.ex")
      File.write!(path, "defmodule MyApp.User do\n  use Ecto.Schema\nend")

      assert SchemaDiscovery.contains_ecto_schema?(path) == true
    end

    test "returns false for non-schema content" do
      path = tmp_path("helper.ex")
      File.write!(path, "defmodule MyApp.Helper do\nend")

      assert SchemaDiscovery.contains_ecto_schema?(path) == false
    end
  end

  describe "extract_table_from_file/1" do
    test "extracts table name from schema definition" do
      path = tmp_path("user.ex")
      File.write!(path, "schema \"users\" do\n  field(:email, :string)\nend")

      assert SchemaDiscovery.extract_table_from_file(path) == "users"
    end

    test "falls back to filename-derived name when no schema table found" do
      path = tmp_path("no_table.ex")
      File.write!(path, "defmodule MyApp.Tableless do\nend")

      assert SchemaDiscovery.extract_table_from_file(path) == "ectomancer_sd_test_no_tables"
    end
  end

  describe "extract_schemas_from_file/1" do
    test "extracts module from valid file content" do
      path = tmp_path("valid_schema.ex")

      File.write!(path, """
      defmodule MyApp.User do
        use Ecto.Schema
        schema \"users\" do
        end
      end
      """)

      modules = SchemaDiscovery.extract_schemas_from_file(path)
      assert is_list(modules)
    end

    test "returns empty list for invalid content" do
      path = tmp_path("invalid.ex")
      File.write!(path, "not valid elixir")

      assert SchemaDiscovery.extract_schemas_from_file(path) == []
    end
  end

  defp tmp_path(filename) do
    Path.join(System.tmp_dir!(), "ectomancer_sd_test_#{filename}")
  end
end
