if Code.ensure_loaded?(Ecto) do
  defmodule Ectomancer.Repo do
    @moduledoc """
    CRUD operations for Ecto schemas exposed via Ectomancer.

    This module provides the actual database operations for the auto-generated
    CRUD tools. It handles:

    - Listing records with filters and pagination
    - Getting single records by primary key
    - Creating records via Ecto changesets
    - Updating records via Ecto changesets
    - Deleting records

    ## Configuration

    The Repo module is automatically detected from your application config:

        config :ectomancer, :repo, MyApp.Repo

    If not configured, it defaults to trying `MyApp.Repo` based on your app's
    module namespace.
    """

    alias Ectomancer.SchemaIntrospection

    @doc """
    Gets the configured Repo module.

    Returns the repo from config or attempts to detect it from the application name.
    """
    @spec repo() :: module() | nil
    def repo do
      case Application.get_env(:ectomancer, :repo) do
        nil -> detect_repo()
        repo_module -> validate_repo(repo_module)
      end
    end

    @doc """
    Detects the Repo module based on the application name.
    """
    @spec detect_repo() :: module() | nil
    def detect_repo do
      Application.started_applications()
      |> Enum.reject(fn {app_name, _, _} -> app_name == :ectomancer end)
      |> Enum.find_value(&find_repo_in_app/1)
    end

    @doc """
    Lists records with optional filters.

    ## Parameters

      * `schema_module` - The Ecto schema module
      * `params` - Map of filter parameters (optional)
      * `opts` - Options including pagination

    ## Examples

        list(MyApp.Accounts.User, %{"email" => "test@example.com"}, limit: 10)
    """
    @spec list(module(), map(), keyword()) :: {:ok, [struct()]} | {:error, any()}
    def list(schema_module, params \\ %{}, opts \\ []) do
      with_repo(fn repo ->
        introspection = SchemaIntrospection.analyze(schema_module)
        {meta_params, filter_params} = extract_meta_params(params)

        query =
          schema_module
          |> build_filter_query(filter_params, introspection.fields)
          |> apply_ordering(meta_params, introspection.fields)
          |> apply_pagination(meta_params, opts)

        {:ok, repo.all(query)}
      end)
    end

    @doc """
    Gets a single record by primary key.

    ## Parameters

      * `schema_module` - The Ecto schema module
      * `params` - Map containing the primary key value

    ## Examples

        get(MyApp.Accounts.User, %{"id" => 123})
    """
    @spec get(module(), map()) :: {:ok, struct() | nil} | {:error, any()}
    def get(schema_module, params) do
      with {:ok, repo} <- get_repo(),
           {:ok, pk_values} <- extract_pk_for_get(schema_module, params) do
        fetch_single_record(repo, schema_module, pk_values)
      end
    rescue
      e -> {:error, "GET failed: #{Exception.message(e)}"}
    end

    @doc """
    Creates a new record.

    ## Parameters

      * `schema_module` - The Ecto schema module
      * `params` - Map of attributes

    ## Examples

        create(MyApp.Accounts.User, %{"email" => "test@example.com", "name" => "Test"})
    """
    @spec create(module(), map()) :: {:ok, struct()} | {:error, Ecto.Changeset.t()}
    def create(schema_module, params) do
      with_repo(fn repo ->
        struct = struct(schema_module)
        attrs = normalize_params(params || %{}, schema_module)

        # Use the schema's changeset function if available, otherwise fallback to cast
        changeset =
          if function_exported?(schema_module, :changeset, 2) do
            schema_module.changeset(struct, attrs)
          else
            writable = writable_fields(schema_module)
            Ecto.Changeset.cast(struct, attrs, writable)
          end

        case repo.insert(changeset) do
          {:ok, record} -> {:ok, record}
          {:error, changeset} -> {:error, changeset}
        end
      end)
    rescue
      e -> {:error, "Database error: #{Exception.message(e)}"}
    end

    @doc """
    Updates an existing record.

    ## Parameters

      * `schema_module` - The Ecto schema module
      * `params` - Map containing primary key and updated attributes

    ## Examples

        update(MyApp.Accounts.User, %{"id" => 123, "name" => "New Name"})
    """
    @spec update(module(), map()) :: {:ok, struct()} | {:error, Ecto.Changeset.t() | :not_found}
    def update(schema_module, params) do
      with {:ok, repo} <- get_repo(),
           {:ok, pk_fields, pk_values} <- extract_pk_for_mutation(schema_module, params || %{}),
           {:ok, record} <- fetch_single_record(repo, schema_module, pk_values) do
        perform_update(repo, schema_module, record, params || %{}, pk_fields)
      end
    end

    @doc """
    Deletes a record.

    ## Parameters

      * `schema_module` - The Ecto schema module
      * `params` - Map containing the primary key value

    ## Examples

        destroy(MyApp.Accounts.User, %{"id" => 123})
    """
    @spec destroy(module(), map()) :: {:ok, struct()} | {:error, :not_found | any()}
    def destroy(schema_module, params) do
      with {:ok, repo} <- get_repo(),
           {:ok, _pk_fields, pk_values} <- extract_pk_for_mutation(schema_module, params),
           {:ok, record} <- fetch_single_record(repo, schema_module, pk_values) do
        perform_destroy(repo, record)
      end
    rescue
      e -> {:error, "DESTROY failed: #{Exception.message(e)}"}
    end

    # Private functions

    defp validate_repo(repo_module) when repo_module == __MODULE__, do: nil
    defp validate_repo(repo_module), do: repo_module

    defp find_repo_in_app({app_name, _, _}) do
      app_module =
        app_name
        |> Atom.to_string()
        |> Macro.camelize()
        |> String.to_atom()

      repo_module = Module.concat(app_module, Repo)

      if Code.ensure_loaded?(repo_module) and function_exported?(repo_module, :all, 1) do
        repo_module
      end
    end

    defp with_repo(fun) do
      case repo() do
        nil -> {:error, :repo_not_configured}
        repo -> fun.(repo)
      end
    end

    defp get_repo do
      case repo() do
        nil -> {:error, :repo_not_configured}
        repo -> {:ok, repo}
      end
    end

    # Extract primary key values for get operation (returns just values)
    defp extract_pk_for_get(schema_module, params) do
      introspection = SchemaIntrospection.analyze(schema_module)
      pk_fields = introspection.primary_key
      field_types = introspection.types

      case extract_primary_key(params, pk_fields, field_types) do
        {:ok, pk_values} -> {:ok, pk_values}
        {:error, reason} -> {:error, reason}
      end
    end

    # Extract primary key for update/destroy operations (returns fields and values)
    defp extract_pk_for_mutation(schema_module, params) do
      introspection = SchemaIntrospection.analyze(schema_module)
      pk_fields = introspection.primary_key
      field_types = introspection.types

      case extract_primary_key(params, pk_fields, field_types) do
        {:ok, pk_values} -> {:ok, pk_fields, pk_values}
        {:error, reason} -> {:error, reason}
      end
    end

    defp fetch_single_record(repo, schema_module, pk_values) do
      query = build_pk_query(schema_module, pk_values)

      case repo.one(query) do
        nil -> {:error, :not_found}
        record -> {:ok, record}
      end
    end

    defp perform_update(repo, schema_module, record, params, pk_fields) do
      update_attrs =
        params
        |> normalize_params(schema_module)
        |> Enum.reject(fn {k, _v} -> k in pk_fields end)
        |> Enum.into(%{})

      # Use the schema's changeset function if available, otherwise fallback to cast
      changeset =
        if function_exported?(schema_module, :changeset, 2) do
          schema_module.changeset(record, update_attrs)
        else
          writable =
            schema_module
            |> writable_fields()
            |> Enum.reject(fn f -> f in pk_fields end)

          Ecto.Changeset.cast(record, update_attrs, writable)
        end

      repo.update(changeset)
    end

    defp perform_destroy(repo, record) do
      repo.delete(record)
    end

    defp normalize_params(params, schema_module) do
      introspection = SchemaIntrospection.analyze(schema_module)
      types = introspection.types

      params
      |> Enum.map(fn
        {k, v} when is_atom(k) ->
          type = Map.get(types, k)
          value = cast_param_value(v, type)
          {k, value}

        {k, v} when is_binary(k) ->
          field = String.to_atom(k)
          type = Map.get(types, field)
          value = cast_param_value(v, type)
          {field, value}
      end)
      |> Enum.into(%{})
    end

    defp cast_param_value(value, :binary_id) when is_binary(value) do
      case Ecto.UUID.cast(value) do
        {:ok, uuid} -> uuid
        :error -> value
      end
    end

    defp cast_param_value(value, Ecto.UUID) when is_binary(value) do
      case Ecto.UUID.cast(value) do
        {:ok, uuid} -> uuid
        :error -> value
      end
    end

    defp cast_param_value(value, _), do: value

    defp writable_fields(schema_module) do
      introspection = SchemaIntrospection.analyze(schema_module)

      introspection.fields
      |> Enum.reject(fn field ->
        field in introspection.primary_key or field in [:inserted_at, :updated_at]
      end)
    end

    @meta_keys ~w(order_by order_dir limit offset)

    defp extract_meta_params(params) do
      {meta, filters} =
        Enum.split_with(params, fn {key, _} -> to_string(key) in @meta_keys end)

      {Map.new(meta, fn {k, v} -> {to_string(k), v} end), Map.new(filters)}
    end

    defp build_filter_query(schema_module, params, fields) do
      import Ecto.Query

      base_query = from(r in schema_module)

      Enum.reduce(params, base_query, fn {field_str, value}, query ->
        {field, operator} = parse_filter_key(to_string(field_str))

        if field in fields do
          apply_filter(query, field, operator, value)
        else
          query
        end
      end)
    end

    defp parse_filter_key(key) do
      suffixes = ~w(_gte _gt _lte _lt _contains _icontains _in _not)

      Enum.find_value(suffixes, {String.to_atom(key), :eq}, fn suffix ->
        if String.ends_with?(key, suffix) do
          base = String.replace_trailing(key, suffix, "")
          op = suffix |> String.trim_leading("_") |> String.to_atom()
          {String.to_atom(base), op}
        end
      end)
    end

    defp apply_filter(query, field, :eq, value) do
      import Ecto.Query
      where(query, [r], field(r, ^field) == ^value)
    end

    defp apply_filter(query, field, :gt, value) do
      import Ecto.Query
      where(query, [r], field(r, ^field) > ^value)
    end

    defp apply_filter(query, field, :gte, value) do
      import Ecto.Query
      where(query, [r], field(r, ^field) >= ^value)
    end

    defp apply_filter(query, field, :lt, value) do
      import Ecto.Query
      where(query, [r], field(r, ^field) < ^value)
    end

    defp apply_filter(query, field, :lte, value) do
      import Ecto.Query
      where(query, [r], field(r, ^field) <= ^value)
    end

    defp apply_filter(query, field, :not, value) do
      import Ecto.Query
      where(query, [r], field(r, ^field) != ^value)
    end

    defp apply_filter(query, field, :contains, value) do
      import Ecto.Query
      pattern = "%#{sanitize_like(value)}%"
      where(query, [r], like(field(r, ^field), ^pattern))
    end

    defp apply_filter(query, field, :icontains, value) do
      import Ecto.Query
      pattern = "%#{sanitize_like(value)}%"
      where(query, [r], ilike(field(r, ^field), ^pattern))
    end

    defp apply_filter(query, field, :in, value) when is_list(value) do
      import Ecto.Query
      where(query, [r], field(r, ^field) in ^value)
    end

    defp apply_filter(query, _field, :in, _value), do: query

    defp sanitize_like(value) do
      value
      |> to_string()
      |> String.replace("\\", "\\\\")
      |> String.replace("%", "\\%")
      |> String.replace("_", "\\_")
    end

    defp apply_ordering(query, meta, fields) do
      import Ecto.Query

      case meta do
        %{"order_by" => order_field} ->
          field = String.to_atom(to_string(order_field))
          dir = parse_order_dir(Map.get(meta, "order_dir", "asc"))

          if field in fields do
            order_by(query, [r], [{^dir, field(r, ^field)}])
          else
            query
          end

        _ ->
          query
      end
    end

    defp parse_order_dir(dir) when is_binary(dir) do
      case String.downcase(dir) do
        "desc" -> :desc
        _ -> :asc
      end
    end

    defp parse_order_dir(_), do: :asc

    defp apply_pagination(query, meta, opts) do
      import Ecto.Query

      limit_val = parse_int(Map.get(meta, "limit")) || Keyword.get(opts, :limit, 100)
      offset_val = parse_int(Map.get(meta, "offset")) || Keyword.get(opts, :offset, 0)

      limit_val = min(limit_val, 100)

      query
      |> limit(^limit_val)
      |> offset(^offset_val)
    end

    defp parse_int(nil), do: nil
    defp parse_int(val) when is_integer(val), do: val

    defp parse_int(val) when is_binary(val) do
      case Integer.parse(val) do
        {int, ""} -> int
        _ -> nil
      end
    end

    defp parse_int(_), do: nil

    defp extract_primary_key(_params, [], _field_types), do: {:error, :no_primary_key}

    defp extract_primary_key(params, pk_fields, field_types) when is_list(pk_fields) do
      values =
        Enum.map(pk_fields, fn pk_field ->
          # Try both string and atom keys
          value =
            case Map.get(params, Atom.to_string(pk_field)) do
              nil -> Map.get(params, pk_field)
              v -> v
            end

          case value do
            nil ->
              {:error, {:missing_primary_key, pk_field}}

            raw_value ->
              # Cast the value based on field type
              field_type = Map.get(field_types, pk_field)
              cast_value = cast_primary_key_value(raw_value, field_type)
              {:ok, {pk_field, cast_value}}
          end
        end)

      case Enum.filter(values, fn {status, _} -> status == :error end) do
        [] ->
          pk_values = Enum.map(values, fn {:ok, {field, value}} -> {field, value} end)
          {:ok, pk_values}

        _errors ->
          {:error, :missing_primary_key}
      end
    end

    # Cast primary key values based on their Ecto type
    defp cast_primary_key_value(value, :binary_id) when is_binary(value) do
      # binary_id fields need to be cast to Ecto.UUID format
      case Ecto.UUID.cast(value) do
        {:ok, casted} -> casted
        :error -> value
      end
    end

    defp cast_primary_key_value(value, :id) when is_binary(value) do
      # Integer ID passed as string (from JSON)
      case Integer.parse(value) do
        {int, ""} -> int
        _ -> value
      end
    end

    defp cast_primary_key_value(value, Ecto.UUID) when is_binary(value) do
      # Explicit UUID type
      case Ecto.UUID.cast(value) do
        {:ok, casted} -> casted
        :error -> value
      end
    end

    defp cast_primary_key_value(value, _type), do: value

    defp build_pk_query(schema_module, pk_values) do
      import Ecto.Query

      base_query = from(r in schema_module)

      Enum.reduce(pk_values, base_query, fn {field, value}, query ->
        where(query, [r], field(r, ^field) == ^value)
      end)
    end
  end
else
  defmodule Ectomancer.Repo do
    @moduledoc false
  end
end
