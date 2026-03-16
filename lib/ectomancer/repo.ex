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

      query =
        schema_module
        |> build_filter_query(params, introspection.fields)
        |> apply_pagination(opts)

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
      attrs = normalize_params(params)
      writable = writable_fields(schema_module)

      changeset = Ecto.Changeset.cast(struct, attrs, writable)
      repo.insert(changeset)
    end)
  rescue
    e -> {:error, "CREATE failed: #{Exception.message(e)}"}
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
         {:ok, pk_fields, pk_values} <- extract_pk_for_mutation(schema_module, params),
         {:ok, record} <- fetch_single_record(repo, schema_module, pk_values) do
      perform_update(repo, schema_module, record, params, pk_fields)
    end
  rescue
    e -> {:error, "UPDATE failed: #{Exception.message(e)}"}
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

    case extract_primary_key(params, pk_fields) do
      {:ok, pk_values} -> {:ok, pk_values}
      {:error, reason} -> {:error, reason}
    end
  end

  # Extract primary key for update/destroy operations (returns fields and values)
  defp extract_pk_for_mutation(schema_module, params) do
    introspection = SchemaIntrospection.analyze(schema_module)
    pk_fields = introspection.primary_key

    case extract_primary_key(params, pk_fields) do
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
      |> normalize_params()
      |> Enum.reject(fn {k, _v} -> k in pk_fields end)
      |> Enum.into(%{})

    writable =
      schema_module
      |> writable_fields()
      |> Enum.reject(fn f -> f in pk_fields end)

    changeset = Ecto.Changeset.cast(record, update_attrs, writable)
    repo.update(changeset)
  rescue
    e -> {:error, Exception.message(e)}
  end

  defp perform_destroy(repo, record) do
    repo.delete(record)
  rescue
    e -> {:error, Exception.message(e)}
  end

  defp normalize_params(params) do
    params
    |> Enum.map(fn {k, v} -> {String.to_atom(k), v} end)
    |> Enum.into(%{})
  end

  defp writable_fields(schema_module) do
    introspection = SchemaIntrospection.analyze(schema_module)

    introspection.fields
    |> Enum.reject(fn field ->
      field in introspection.primary_key or field in [:inserted_at, :updated_at]
    end)
  end

  defp build_filter_query(schema_module, params, fields) do
    import Ecto.Query

    base_query = from(r in schema_module)

    Enum.reduce(params, base_query, fn {field_str, value}, query ->
      field = String.to_atom(field_str)

      if field in fields do
        where(query, [r], field(r, ^field) == ^value)
      else
        query
      end
    end)
  end

  defp apply_pagination(query, opts) do
    import Ecto.Query

    limit = Keyword.get(opts, :limit, 100)
    offset = Keyword.get(opts, :offset, 0)

    query
    |> limit(^limit)
    |> offset(^offset)
  end

  defp extract_primary_key(_params, []), do: {:error, :no_primary_key}

  defp extract_primary_key(params, pk_fields) when is_list(pk_fields) do
    values =
      Enum.map(pk_fields, fn pk_field ->
        key = Atom.to_string(pk_field)

        case Map.get(params, key) do
          nil -> {:error, {:missing_primary_key, pk_field}}
          value -> {:ok, {pk_field, value}}
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

  defp build_pk_query(schema_module, pk_values) do
    import Ecto.Query

    base_query = from(r in schema_module)

    Enum.reduce(pk_values, base_query, fn {field, value}, query ->
      where(query, [r], field(r, ^field) == ^value)
    end)
  end
end
