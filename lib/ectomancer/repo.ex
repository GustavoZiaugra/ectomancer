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
    alias Ectomancer.Repo.Filtering

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
      Ectomancer.Telemetry.repo_span(:list, schema_module, fn ->
        try do
          with_repo(opts, fn repo ->
            introspection = SchemaIntrospection.analyze(schema_module)
            {meta_params, filter_params} = Filtering.extract_meta_params(params)

            query =
              schema_module
              |> Filtering.build_filter_query(filter_params, introspection.fields)
              |> Filtering.apply_scope(Keyword.get(opts, :scope))
              |> Filtering.apply_soft_delete_filter(schema_module, meta_params)
              |> Filtering.apply_ordering(meta_params, introspection.fields)
              |> Filtering.apply_pagination(meta_params, opts)

            results = repo.all(query)
            {:ok, maybe_preload(repo, results, opts)}
          end)
        rescue
          DBConnection.ConnectionError -> {:error, {:db, "connection_lost"}}
          e -> {:error, {:unexpected, "List failed: #{Exception.message(e)}"}}
        end
      end)
    end

    @doc """
    Gets a single record by primary key.

    ## Parameters

      * `schema_module` - The Ecto schema module
      * `params` - Map containing the primary key value
      * `opts` - Options including `:preload` for eager-loading associations

    ## Examples

        get(MyApp.Accounts.User, %{"id" => 123})
        get(MyApp.Accounts.User, %{"id" => 123}, preload: [:posts, :comments])
    """
    @spec get(module(), map(), keyword()) :: {:ok, struct() | nil} | {:error, any()}
    def get(schema_module, params, opts \\ []) do
      Ectomancer.Telemetry.repo_span(:get, schema_module, fn ->
        try do
          with {:ok, repo} <- get_repo(opts),
               {:ok, pk_values} <- extract_pk_for_get(schema_module, params) do
            result = fetch_single_record(repo, schema_module, pk_values, opts)
            handle_get_result(repo, schema_module, params, result, opts)
          end
        rescue
          Ecto.NoResultsError -> {:error, :not_found}
          Ecto.StaleEntryError -> {:error, :stale_entry}
          DBConnection.ConnectionError -> {:error, {:db, "connection_lost"}}
          e -> {:error, {:unexpected, "GET failed: #{Exception.message(e)}"}}
        end
      end)
    end

    defp handle_get_result(repo, schema_module, params, result, opts) do
      case result do
        {:ok, record} ->
          sd_field = SchemaIntrospection.soft_delete_field(schema_module)

          if sd_field && Map.get(record, sd_field) && !Map.get(params, "include_deleted", false) do
            {:error, :not_found}
          else
            {:ok, maybe_preload(repo, record, opts)}
          end

        error ->
          error
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
    def create(schema_module, params, opts \\ []) do
      Ectomancer.Telemetry.repo_span(:create, schema_module, fn ->
        try do
          with_repo(opts, fn repo ->
            struct = struct(schema_module)
            attrs = normalize_params(params || %{}, schema_module)

            changeset =
              changeset_for(schema_module, struct, attrs, writable_fields(schema_module))

            case repo.insert(changeset) do
              {:ok, record} -> {:ok, record}
              {:error, changeset} -> {:error, changeset}
            end
          end)
        rescue
          DBConnection.ConnectionError -> {:error, {:db, "connection_lost"}}
          Ecto.StaleEntryError -> {:error, :stale_entry}
          e -> {:error, {:unexpected, "Create failed: #{Exception.message(e)}"}}
        end
      end)
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
    def update(schema_module, params, opts \\ []) do
      Ectomancer.Telemetry.repo_span(:update, schema_module, fn ->
        try do
          with {:ok, repo} <- get_repo(opts),
               {:ok, pk_fields, pk_values} <-
                 extract_pk_for_mutation(schema_module, params || %{}),
               {:ok, record} <- fetch_single_record(repo, schema_module, pk_values, opts) do
            perform_update(repo, schema_module, record, params || %{}, pk_fields)
          end
        rescue
          DBConnection.ConnectionError -> {:error, {:db, "connection_lost"}}
          Ecto.StaleEntryError -> {:error, :stale_entry}
          e -> {:error, {:unexpected, "Update failed: #{Exception.message(e)}"}}
        end
      end)
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
    def destroy(schema_module, params, opts \\ []) do
      Ectomancer.Telemetry.repo_span(:destroy, schema_module, fn ->
        try do
          with {:ok, repo} <- get_repo(opts),
               {:ok, _pk_fields, pk_values} <- extract_pk_for_mutation(schema_module, params),
               {:ok, record} <- fetch_single_record(repo, schema_module, pk_values, opts) do
            perform_destroy(repo, schema_module, record)
          end
        rescue
          DBConnection.ConnectionError -> {:error, {:db, "connection_lost"}}
          Ecto.StaleEntryError -> {:error, :stale_entry}
          e -> {:error, {:unexpected, "Destroy failed: #{Exception.message(e)}"}}
        end
      end)
    end

    @doc """
    Upserts a record - inserts a new record or updates an existing one based on conflict target.

    ## Parameters

      * `schema_module` - The Ecto schema module
      * `params` - Map of attributes
      * `opts` - Options including `:conflict_target` and `:on_conflict`

    ## Options

      * `:conflict_target` - Field(s) to check for conflicts. Single atom or list of atoms.
      * `:on_conflict` - What to do on conflict. `:replace_all` (default) or `[set: [...]]`

    ## Examples

        upsert(MyApp.Accounts.User, %{"email" => "test@example.com", "name" => "Test"},
          conflict_target: :email,
          on_conflict: :replace_all
        )

    Returns `{:ok, {record, :inserted}}` or `{:ok, {record, :updated}}`.
    """
    @spec upsert(module(), map(), keyword()) ::
            {:ok, {struct(), atom()}} | {:error, Ecto.Changeset.t()}
    def upsert(schema_module, params, opts \\ []) do
      Ectomancer.Telemetry.repo_span(:upsert, schema_module, fn ->
        try do
          with {:ok, repo} <- get_repo(opts) do
            attrs = normalize_params(params || %{}, schema_module)
            do_upsert(repo, schema_module, attrs, opts)
          end
        rescue
          DBConnection.ConnectionError -> {:error, {:db, "connection_lost"}}
          Ecto.StaleEntryError -> {:error, :stale_entry}
          e -> {:error, {:unexpected, "Upsert failed: #{Exception.message(e)}"}}
        end
      end)
    end

    defp do_upsert(repo, schema_module, attrs, opts) do
      conflict_target = Keyword.get(opts, :conflict_target)

      if conflict_target do
        upsert_with_conflict(repo, schema_module, attrs, conflict_target, opts)
      else
        insert_for_upsert(repo, schema_module, attrs, :inserted)
      end
    end

    defp upsert_with_conflict(repo, schema_module, attrs, conflict_target, opts) do
      conflict_fields = List.wrap(conflict_target)
      conflict_values = Map.take(attrs, conflict_fields)

      if has_all_conflict_values?(conflict_values, conflict_fields) do
        query = build_upsert_find_query(schema_module, conflict_values)

        query =
          query
          |> Filtering.apply_scope(Keyword.get(opts, :scope))

        case repo.one(query) do
          nil -> insert_for_upsert(repo, schema_module, attrs, :inserted)
          existing -> upsert_update_existing(repo, schema_module, existing, attrs, opts)
        end
      else
        insert_for_upsert(repo, schema_module, attrs, :inserted)
      end
    end

    defp has_all_conflict_values?(conflict_values, conflict_fields) do
      map_size(conflict_values) == length(conflict_fields) and conflict_values != %{}
    end

    defp insert_for_upsert(repo, schema_module, attrs, action) do
      struct = struct(schema_module)

      changeset = build_create_changeset(schema_module, struct, attrs)

      case repo.insert(changeset) do
        {:ok, record} -> {:ok, {record, action}}
        {:error, changeset} -> {:error, changeset}
      end
    end

    defp upsert_update_existing(repo, schema_module, existing, attrs, opts) do
      on_conflict = Keyword.get(opts, :on_conflict, :replace_all)
      conflict_target = Keyword.get(opts, :conflict_target)
      conflict_fields = List.wrap(conflict_target)
      pk_fields = SchemaIntrospection.analyze(schema_module).primary_key

      update_attrs = resolve_upsert_update_attrs(attrs, on_conflict, conflict_fields)

      sd_field = SchemaIntrospection.soft_delete_field(schema_module)

      update_attrs =
        if is_nil(sd_field), do: update_attrs, else: Map.put(update_attrs, sd_field, nil)

      writable =
        schema_module
        |> writable_fields()
        |> Enum.reject(fn f -> f in pk_fields end)

      writable =
        if not is_nil(sd_field) and sd_field not in writable do
          [sd_field | writable]
        else
          writable
        end

      changeset = changeset_for(schema_module, existing, update_attrs, writable)

      case repo.update(changeset) do
        {:ok, record} -> {:ok, {record, :updated}}
        {:error, changeset} -> {:error, changeset}
      end
    end

    defp resolve_upsert_update_attrs(attrs, :replace_all, _conflict_fields) do
      attrs
    end

    defp resolve_upsert_update_attrs(attrs, [set: fields], _conflict_fields)
         when is_list(fields) do
      Map.take(attrs, fields)
    end

    defp resolve_upsert_update_attrs(_attrs, _on_conflict, _conflict_fields) do
      %{}
    end

    defp build_upsert_find_query(schema_module, conflict_values) do
      import Ecto.Query

      Enum.reduce(conflict_values, from(r in schema_module), fn {field, value}, query ->
        where(query, [r], field(r, ^field) == ^value)
      end)
    end

    @doc """
    Restores a soft-deleted record by setting its soft-delete field to `nil`.

    ## Parameters

      * `schema_module` - The Ecto schema module
      * `params` - Map containing the primary key value

    ## Examples

        restore(MyApp.Accounts.User, %{\"id\" => 123})
    """
    @spec restore(module(), map()) ::
            {:ok, struct()} | {:error, :not_found | :not_soft_deletable | any()}
    def restore(schema_module, params, opts \\ []) do
      Ectomancer.Telemetry.repo_span(:restore, schema_module, fn ->
        try do
          with {:ok, repo} <- get_repo(opts),
               {:ok, _pk_fields, pk_values} <- extract_pk_for_mutation(schema_module, params),
               {:ok, record} <- fetch_single_record(repo, schema_module, pk_values, opts) do
            sd_field = SchemaIntrospection.soft_delete_field(schema_module)

            if sd_field do
              perform_restore(repo, record, sd_field)
            else
              {:error, :not_soft_deletable}
            end
          end
        rescue
          DBConnection.ConnectionError -> {:error, {:db, "connection_lost"}}
          Ecto.StaleEntryError -> {:error, :stale_entry}
          e -> {:error, {:unexpected, "Restore failed: #{Exception.message(e)}"}}
        end
      end)
    end

    @doc """
    Batch creates multiple records in a single transaction.

    ## Parameters

      * `schema_module` - The Ecto schema module
      * `params` - Map containing `"records"` key with a list of attribute maps
      * `opts` - Options including `:scope`, `:repo`, `:batch_size`

    ## Examples

        batch_create(MyApp.Accounts.User, %{
          "records" => [
            %{"email" => "a@b.com", "name" => "Alice"},
            %{"email" => "b@c.com", "name" => "Bob"}
          ]
        })
    """
    @spec batch_create(module(), map(), keyword()) ::
            {:ok, %{succeeded: list(), failed: list(), total: non_neg_integer()}}
            | {:error, any()}
    def batch_create(schema_module, params, opts \\ []) do
      Ectomancer.Telemetry.repo_span(:batch_create, schema_module, fn ->
        try do
          records = Map.get(params || %{}, "records", [])
          batch_size = Keyword.get(opts, :batch_size, 100)

          if length(records) > batch_size do
            {:error, {:batch_size_exceeded, batch_size}}
          else
            with_repo(opts, fn repo ->
              run_batch(repo, schema_module, records, opts, fn attrs ->
                perform_batch_create(repo, schema_module, attrs)
              end)
            end)
          end
        rescue
          DBConnection.ConnectionError -> {:error, {:db, "connection_lost"}}
          e -> {:error, {:unexpected, "Batch create failed: #{Exception.message(e)}"}}
        end
      end)
    end

    @doc """
    Batch updates multiple records in a single transaction.

    ## Parameters

      * `schema_module` - The Ecto schema module
      * `params` - Map containing `"records"` key with a list of maps (each must include the primary key)
      * `opts` - Options including `:scope`, `:repo`, `:batch_size`

    ## Examples

        batch_update(MyApp.Accounts.User, %{
          "records" => [
            %{"id" => 1, "name" => "Alice Updated"},
            %{"id" => 2, "email" => "b@new.com"}
          ]
        })
    """
    @spec batch_update(module(), map(), keyword()) ::
            {:ok, %{succeeded: list(), failed: list(), total: non_neg_integer()}}
            | {:error, any()}
    def batch_update(schema_module, params, opts \\ []) do
      Ectomancer.Telemetry.repo_span(:batch_update, schema_module, fn ->
        try do
          records = Map.get(params || %{}, "records", [])
          batch_size = Keyword.get(opts, :batch_size, 100)

          if length(records) > batch_size do
            {:error, {:batch_size_exceeded, batch_size}}
          else
            with_repo(opts, fn repo ->
              run_batch(repo, schema_module, records, opts, fn record_attrs ->
                perform_batch_update(repo, schema_module, record_attrs, opts)
              end)
            end)
          end
        rescue
          DBConnection.ConnectionError -> {:error, {:db, "connection_lost"}}
          e -> {:error, {:unexpected, "Batch update failed: #{Exception.message(e)}"}}
        end
      end)
    end

    @doc """
    Batch destroys multiple records in a single transaction.

    ## Parameters

      * `schema_module` - The Ecto schema module
      * `params` - Map containing `"ids"` key with a list of primary key values
      * `opts` - Options including `:scope`, `:repo`, `:batch_size`

    ## Examples

        batch_destroy(MyApp.Accounts.User, %{
          "ids" => [1, 2, 3]
        })
    """
    @spec batch_destroy(module(), map(), keyword()) ::
            {:ok, %{succeeded: list(), failed: list(), total: non_neg_integer()}}
            | {:error, any()}
    def batch_destroy(schema_module, params, opts \\ []) do
      Ectomancer.Telemetry.repo_span(:batch_destroy, schema_module, fn ->
        try do
          ids = Map.get(params || %{}, "ids", [])
          batch_size = Keyword.get(opts, :batch_size, 100)

          if length(ids) > batch_size do
            {:error, {:batch_size_exceeded, batch_size}}
          else
            with_repo(opts, fn repo ->
              run_batch(repo, schema_module, ids, opts, fn raw_id ->
                perform_batch_destroy(repo, schema_module, raw_id, opts)
              end)
            end)
          end
        rescue
          DBConnection.ConnectionError -> {:error, {:db, "connection_lost"}}
          e -> {:error, {:unexpected, "Batch destroy failed: #{Exception.message(e)}"}}
        end
      end)
    end

    defp perform_batch_create(repo, schema_module, attrs) do
      struct = struct(schema_module)
      attrs = normalize_params(attrs, schema_module)
      changeset = build_create_changeset(schema_module, struct, attrs)

      case repo.insert(changeset) do
        {:ok, record} -> {:ok, record}
        {:error, changeset} -> {:error, attrs, changeset}
      end
    end

    defp build_create_changeset(schema_module, struct, attrs) do
      changeset_for(schema_module, struct, attrs, writable_fields(schema_module))
    end

    defp perform_batch_destroy(repo, schema_module, raw_id, opts) do
      introspection = SchemaIntrospection.analyze(schema_module)
      pk_field = hd(introspection.primary_key)
      field_type = Map.get(introspection.types, pk_field)
      cast_id = cast_primary_key_value(raw_id, field_type)
      pk_values = [{pk_field, cast_id}]
      scope = Keyword.get(opts, :scope)

      query =
        schema_module
        |> build_pk_query(pk_values)
        |> Filtering.apply_scope(scope)

      case repo.one(query) do
        nil ->
          {:error, raw_id, :not_found}

        record ->
          sd_field = SchemaIntrospection.soft_delete_field(schema_module)

          result =
            if sd_field do
              now = NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)
              changeset = Ecto.Changeset.change(record, %{sd_field => now})
              repo.update(changeset)
            else
              repo.delete(record)
            end

          case result do
            {:ok, record} -> {:ok, record}
            {:error, changeset} -> {:error, raw_id, changeset}
          end
      end
    end

    defp perform_batch_update(repo, schema_module, record_attrs, opts) do
      pk_fields = SchemaIntrospection.analyze(schema_module).primary_key
      pk_values = extract_pk_values(record_attrs, pk_fields, schema_module)

      case pk_values do
        {:error, reason} ->
          {:error, record_attrs, reason}

        {:ok, pk_values} ->
          update_record_by_pk(repo, schema_module, pk_values, record_attrs, pk_fields, opts)
      end
    end

    defp update_record_by_pk(repo, schema_module, pk_values, record_attrs, pk_fields, opts) do
      scope = Keyword.get(opts, :scope)

      query =
        schema_module
        |> build_pk_query(pk_values)
        |> Filtering.apply_scope(scope)

      case repo.one(query) do
        nil ->
          {:error, record_attrs, :not_found}

        record ->
          update_attrs =
            record_attrs
            |> normalize_params(schema_module)
            |> Enum.reject(fn {k, _v} -> k in pk_fields end)
            |> Enum.into(%{})

          changeset = build_changeset(schema_module, record, update_attrs, pk_fields)

          case repo.update(changeset) do
            {:ok, record} -> {:ok, record}
            {:error, changeset} -> {:error, record_attrs, changeset}
          end
      end
    end

    defp build_changeset(schema_module, record, update_attrs, pk_fields) do
      writable =
        schema_module
        |> writable_fields()
        |> Enum.reject(fn f -> f in pk_fields end)

      changeset_for(schema_module, record, update_attrs, writable)
    end

    defp run_batch(repo, _schema_module, items, _opts, operation) do
      results =
        repo.transaction(fn ->
          Enum.map(items, fn item ->
            try do
              case operation.(item) do
                {:ok, record} -> %{status: :ok, record: record}
                {:error, input, errors} -> %{status: :error, input: input, errors: errors}
              end
            rescue
              e ->
                %{status: :error, input: item, errors: Exception.message(e)}
            end
          end)
        end)

      case results do
        {:ok, results} ->
          succeeded = Enum.filter(results, &(&1.status == :ok))
          failed = Enum.filter(results, &(&1.status != :ok))
          {:ok, %{succeeded: succeeded, failed: failed, total: length(results)}}

        {:error, reason} ->
          {:error, reason}
      end
    end

    defp extract_pk_values(params, pk_fields, schema_module) when is_list(pk_fields) do
      field_types = SchemaIntrospection.analyze(schema_module).types

      values =
        Enum.map(pk_fields, fn pk_field ->
          value =
            case Map.get(params, Atom.to_string(pk_field)) do
              nil -> Map.get(params, pk_field)
              v -> v
            end

          case value do
            nil ->
              {:error, {:missing_primary_key, pk_field}}

            raw_value ->
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

    # Private functions

    @doc false
    def validate_repo(repo_module) when repo_module == __MODULE__, do: nil
    @doc false
    def validate_repo(repo_module), do: repo_module

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

    defp with_repo(opts, fun) do
      configured = repo_for_opts(opts)
      if configured, do: fun.(configured), else: {:error, :repo_not_configured}
    end

    defp get_repo(opts) do
      configured = repo_for_opts(opts)
      if configured, do: {:ok, configured}, else: {:error, :repo_not_configured}
    end

    defp repo_for_opts(opts) do
      case opts[:repo] do
        nil -> repo()
        mod -> validate_repo(mod)
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

    defp fetch_single_record(repo, schema_module, pk_values, opts) do
      query =
        schema_module
        |> build_pk_query(pk_values)
        |> Filtering.apply_scope(Keyword.get(opts, :scope))

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

      writable =
        schema_module
        |> writable_fields()
        |> Enum.reject(fn f -> f in pk_fields end)

      changeset = changeset_for(schema_module, record, update_attrs, writable)
      repo.update(changeset)
    end

    defp perform_destroy(repo, schema_module, record) do
      sd_field = SchemaIntrospection.soft_delete_field(schema_module)

      if sd_field do
        perform_soft_delete(repo, record, sd_field)
      else
        repo.delete(record)
      end
    end

    defp perform_soft_delete(repo, record, sd_field) do
      now = NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)
      changeset = Ecto.Changeset.change(record, %{sd_field => now})
      repo.update(changeset)
    end

    defp perform_restore(repo, record, sd_field) do
      changeset = Ecto.Changeset.change(record, %{sd_field => nil})
      repo.update(changeset)
    end

    defdelegate extract_meta_params(params), to: Filtering
    defdelegate parse_filter_key(key), to: Filtering
    defdelegate sanitize_like(value), to: Filtering
    defdelegate parse_order_dir(dir), to: Filtering
    defdelegate parse_int(val), to: Filtering

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

    @doc false
    def cast_param_value(value, :binary_id) when is_binary(value) do
      case Ecto.UUID.cast(value) do
        {:ok, uuid} -> uuid
        :error -> value
      end
    end

    @doc false
    def cast_param_value(value, Ecto.UUID) when is_binary(value) do
      case Ecto.UUID.cast(value) do
        {:ok, uuid} -> uuid
        :error -> value
      end
    end

    @doc false
    def cast_param_value(value, _), do: value

    defp writable_fields(schema_module) do
      introspection = SchemaIntrospection.analyze(schema_module)

      introspection.fields
      |> Enum.reject(fn field ->
        field in introspection.primary_key or field in [:inserted_at, :updated_at]
      end)
    end

    defp changeset_for(schema_module, struct, attrs, writable_fields) do
      if function_exported?(schema_module, :changeset, 2) do
        schema_module.changeset(struct, attrs)
      else
        Ecto.Changeset.cast(struct, attrs, writable_fields)
      end
    end

    @doc """
    Validates dynamic include requests against allowed preloadable associations.

    Returns the opts keyword list with merged preloads.
    """
    @spec validate_includes(list() | nil, :all | list(atom()), keyword()) :: keyword()
    def validate_includes(nil, _allowed, opts), do: opts
    def validate_includes([], _allowed, opts), do: opts

    def validate_includes(include, :all, opts) when is_list(include) do
      validated =
        include
        |> Enum.map(&String.to_atom/1)
        |> Enum.reject(&is_nil(&1))

      existing = Keyword.get(opts, :preload, [])
      Keyword.put(opts, :preload, existing ++ validated)
    end

    def validate_includes(include, allowed, opts) when is_list(include) and is_list(allowed) do
      allowed_strs = Enum.map(allowed, &Atom.to_string/1)

      validated =
        include
        |> Enum.filter(&(&1 in allowed_strs))
        |> Enum.map(&String.to_atom/1)

      existing = Keyword.get(opts, :preload, [])
      Keyword.put(opts, :preload, existing ++ validated)
    end

    defp maybe_preload(_repo, record, _opts) when is_nil(record), do: nil

    defp maybe_preload(repo, record, opts) when not is_list(record) do
      case Keyword.get(opts, :preload) do
        nil -> record
        preloads -> repo.preload(record, preloads)
      end
    end

    defp maybe_preload(repo, records, opts) when is_list(records) do
      case Keyword.get(opts, :preload) do
        nil -> records
        preloads -> repo.preload(records, preloads)
      end
    end

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
    @doc false
    def cast_primary_key_value(value, :binary_id) when is_binary(value) do
      # binary_id fields need to be cast to Ecto.UUID format
      case Ecto.UUID.cast(value) do
        {:ok, casted} -> casted
        :error -> value
      end
    end

    @doc false
    def cast_primary_key_value(value, :id) when is_binary(value) do
      # Integer ID passed as string (from JSON)
      case Integer.parse(value) do
        {int, ""} -> int
        _ -> value
      end
    end

    @doc false
    def cast_primary_key_value(value, Ecto.UUID) when is_binary(value) do
      # Explicit UUID type
      case Ecto.UUID.cast(value) do
        {:ok, casted} -> casted
        :error -> value
      end
    end

    @doc false
    def cast_primary_key_value(value, _type), do: value

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
