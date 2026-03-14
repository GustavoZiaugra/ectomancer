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
      nil ->
        # Try to detect based on app name
        detected = detect_repo()
        # Make sure we don't return ourselves
        if detected == __MODULE__ do
          nil
        else
          detected
        end

      repo_module ->
        # Make sure configured repo is not this module
        if repo_module == __MODULE__ do
          nil
        else
          repo_module
        end
    end
  end

  @doc """
  Detects the Repo module based on the application name.
  """
  @spec detect_repo() :: module() | nil
  def detect_repo do
    # Get the application name from the current process
    # This is a heuristic - checks if MyApp.Repo exists
    apps = Application.started_applications()

    # Try to find a repo in started apps (exclude :ectomancer itself)
    apps
    |> Enum.reject(fn {app_name, _, _} -> app_name == :ectomancer end)
    |> Enum.find_value(&find_repo_in_app/1)
  end

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
    repo = repo()

    if is_nil(repo) do
      {:error, :repo_not_configured}
    else
      introspection = SchemaIntrospection.analyze(schema_module)

      query =
        schema_module
        |> build_filter_query(params, introspection.fields)
        |> apply_pagination(opts)

      try do
        records = repo.all(query)
        {:ok, records}
      rescue
        e -> {:error, Exception.message(e)}
      end
    end
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
    repo = repo()

    if is_nil(repo) do
      {:error, :repo_not_configured}
    else
      introspection = SchemaIntrospection.analyze(schema_module)
      pk_fields = introspection.primary_key

      case extract_primary_key(params, pk_fields) do
        {:ok, pk_values} ->
          query =
            schema_module
            |> build_pk_query(pk_fields, pk_values)

          try do
            record = repo.one(query)

            if record do
              {:ok, record}
            else
              {:error, :not_found}
            end
          rescue
            e -> {:error, Exception.message(e)}
          end

        {:error, reason} ->
          {:error, reason}
      end
    end
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
    repo = repo()

    if is_nil(repo) do
      {:error, :repo_not_configured}
    else
      # Build a simple changeset
      struct = struct(schema_module)

      # Convert string keys to atoms and filter to writable fields
      attrs =
        params
        |> Enum.map(fn {k, v} -> {String.to_atom(k), v} end)
        |> Enum.into(%{})

      changeset = Ecto.Changeset.cast(struct, attrs, writable_fields(schema_module))

      try do
        repo.insert(changeset)
      rescue
        e -> {:error, Exception.message(e)}
      end
    end
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
         {:ok, pk_fields, pk_values} <- extract_pk_for_update(schema_module, params),
         {:ok, record} <- fetch_record_for_update(repo, schema_module, pk_fields, pk_values) do
      perform_update(repo, schema_module, record, params, pk_fields)
    end
  end

  defp get_repo do
    case repo() do
      nil -> {:error, :repo_not_configured}
      repo -> {:ok, repo}
    end
  end

  defp extract_pk_for_update(schema_module, params) do
    introspection = SchemaIntrospection.analyze(schema_module)
    pk_fields = introspection.primary_key

    case extract_primary_key(params, pk_fields) do
      {:ok, pk_values} -> {:ok, pk_fields, pk_values}
      {:error, reason} -> {:error, reason}
    end
  end

  defp fetch_record_for_update(repo, schema_module, pk_fields, pk_values) do
    query = build_pk_query(schema_module, pk_fields, pk_values)

    case repo.one(query) do
      nil -> {:error, :not_found}
      record -> {:ok, record}
    end
  end

  defp perform_update(repo, schema_module, record, params, pk_fields) do
    update_attrs =
      params
      |> Enum.reject(fn {k, _v} -> String.to_atom(k) in pk_fields end)
      |> Enum.map(fn {k, v} -> {String.to_atom(k), v} end)
      |> Enum.into(%{})

    writable = writable_fields(schema_module) |> Enum.reject(fn f -> f in pk_fields end)
    changeset = Ecto.Changeset.cast(record, update_attrs, writable)

    repo.update(changeset)
  rescue
    e -> {:error, Exception.message(e)}
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
         {:ok, pk_fields, pk_values} <- extract_pk_for_destroy(schema_module, params),
         {:ok, record} <- fetch_record_for_destroy(repo, schema_module, pk_fields, pk_values) do
      perform_destroy(repo, record)
    end
  end

  defp extract_pk_for_destroy(schema_module, params) do
    introspection = SchemaIntrospection.analyze(schema_module)
    pk_fields = introspection.primary_key

    case extract_primary_key(params, pk_fields) do
      {:ok, pk_values} -> {:ok, pk_fields, pk_values}
      {:error, reason} -> {:error, reason}
    end
  end

  defp fetch_record_for_destroy(repo, schema_module, pk_fields, pk_values) do
    query = build_pk_query(schema_module, pk_fields, pk_values)

    case repo.one(query) do
      nil -> {:error, :not_found}
      record -> {:ok, record}
    end
  end

  defp perform_destroy(repo, record) do
    repo.delete(record)
  rescue
    e -> {:error, Exception.message(e)}
  end

  # Helper functions

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
    values = extract_pk_values(params, pk_fields)

    case Enum.filter(values, fn {status, _} -> status == :error end) do
      [] ->
        pk_values = Enum.map(values, fn {:ok, {field, value}} -> {field, value} end)
        {:ok, pk_values}

      _errors ->
        {:error, :missing_primary_key}
    end
  end

  defp extract_pk_values(params, pk_fields) do
    Enum.map(pk_fields, fn pk_field ->
      key = Atom.to_string(pk_field)

      case Map.get(params, key) do
        nil -> {:error, {:missing_primary_key, pk_field}}
        value -> {:ok, {pk_field, value}}
      end
    end)
  end

  defp build_pk_query(schema_module, _pk_fields, pk_values) do
    import Ecto.Query

    base_query = from(r in schema_module)

    Enum.reduce(pk_values, base_query, fn {field, value}, query ->
      where(query, [r], field(r, ^field) == ^value)
    end)
  end
end
