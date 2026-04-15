defmodule Ectomancer.Installer.SchemaDiscovery do
  @moduledoc """
  Discovers Ecto schemas in a Phoenix/Elixir project.

  Supports two discovery methods:
  1. File scanning: Scans lib/**/*.ex files for `use Ecto.Schema`
  2. Module introspection: Uses Code.ensure_loaded? for compiled modules

  ## Usage

      schemas = Ectomancer.Installer.SchemaDiscovery.discover()

      # Returns: [
      #   %{
      #     module: MyApp.Accounts.User,
      #     table: "users",
      #     context: "Accounts",
      #     associations: [:posts],
      #     writable_fields: [:email, :name]
      #   },
      #   ...
      # ]
  """

  @doc """
  Discovers all Ecto schemas in the current project.

  Tries module introspection first (faster for compiled code),
  then falls back to file scanning for any missed schemas.
  """
  @spec discover() ::
          list(%{
            module: module(),
            table: String.t() | nil,
            context: String.t() | nil,
            associations: [atom()],
            writable_fields: [atom()]
          })
  def discover do
    (module_introspection() ++ file_discovery())
    |> Enum.filter(& &1.table)
    |> Enum.uniq_by(& &1.module)
  end

  @doc """
  Discovers schemas using module introspection.

  Works best for compiled modules. Returns nil for embedded schemas.
  """
  @spec module_introspection() :: list(map())
  def module_introspection do
    modules =
      :code.all_loaded()
      |> Enum.map(&elem(&1, 0))
      |> Enum.filter(&ecto_schema_module?/1)

    Enum.map(modules, fn module ->
      schema_info = analyze_module(module)

      %{
        module: module,
        table: schema_info.table,
        context: extract_context(module),
        associations: schema_info.associations,
        writable_fields: schema_info.writable_fields
      }
    end)
  end

  @doc """
  Discovers schemas by scanning source files.

  Useful for finding schemas that haven't been compiled yet.
  """
  @spec file_discovery() :: list(map())
  def file_discovery do
    lib_path = Path.join([File.cwd!(), "lib"])

    unless File.exists?(lib_path) do
      []
    end

    schema_files =
      Path.wildcard(Path.join([lib_path, "**/*.ex"]))
      |> Enum.filter(&contains_ecto_schema?/1)

    Enum.flat_map(schema_files, fn file_path ->
      extract_schemas_from_file(file_path)
    end)
  end

  @doc """
  Analyzes a single schema module and extracts metadata.
  """
  @spec analyze_module(module()) :: %{
          table: String.t() | nil,
          associations: [atom()],
          writable_fields: [atom()]
        }
  def analyze_module(module) do
    try do
      table = module.__schema__(:table) || nil
      associations = module.__schema__(:associations)
      writable_fields = Ectomancer.SchemaIntrospection.writable_fields(module)

      %{
        table: table,
        associations: associations,
        writable_fields: writable_fields
      }
    rescue
      _ -> %{table: nil, associations: [], writable_fields: []}
    end
  end

  # Private functions

  defp ecto_schema_module?(module) do
    Code.ensure_loaded?(module) and
      function_exported?(module, :__schema__, 1) and
      !function_exported?(module, :__schema__, 2)
  end

  defp contains_ecto_schema?(file_path) do
    case File.read(file_path) do
      {:ok, content} ->
        String.contains?(content, "use Ecto.Schema") or
          String.contains?(content, "use Ecto.Schema,")

      _ ->
        false
    end
  end

  defp extract_schemas_from_file(file_path) do
    with {:ok, content} <- File.read(file_path),
         {:ok, ast} <- Code.string_to_quoted(content) do
      case ast do
        {:defmodule, {module_name, _module_meta}, _env} ->
          module_name
          |> extract_module_info(file_path)
          |> case do
            nil -> []
            info -> [info]
          end

        _ ->
          []
      end
    else
      _ -> []
    end
  end

  defp extract_module_info(module_name, file_path) do
    full_module_name = module_name

    try do
      module = Module.concat(full_module_name)

      unless function_exported?(module, :__schema__, 1) do
        nil
      end

      table = extract_table_from_file(file_path)
      context = extract_context(full_module_name)

      associations =
        try do
          module.__schema__(:associations)
        rescue
          _ -> []
        end

      writable_fields =
        try do
          Ectomancer.SchemaIntrospection.writable_fields(module)
        rescue
          _ -> []
        end

      %{
        module: module,
        table: table,
        context: context,
        associations: associations,
        writable_fields: writable_fields
      }
    rescue
      _ -> nil
    end
  end

  defp extract_table_from_file(file_path) do
    file_content = File.read!(file_path)

    schema_pattern = ~r/schema\s+["'](\w+)["']\s+do/

    case Regex.run(schema_pattern, file_content) do
      [_, table_name] ->
        table_name

      _ ->
        module_name = file_path |> Path.basename() |> String.replace(".ex", "")
        Macro.underscore(module_name) |> String.replace("_", "")
    end
  end

  @doc false
  def extract_context(full_module_name) when is_atom(full_module_name) do
    full_module_name
    |> Module.split()
    |> extract_context_from_parts()
  end

  @doc false
  def extract_context(full_module_name) when is_binary(full_module_name) do
    parts = String.split(full_module_name, ".")
    extract_context_from_parts(parts)
  end

  defp extract_context_from_parts(parts) do
    case parts do
      [_, context, _] -> context
      _ -> nil
    end
  end
end
