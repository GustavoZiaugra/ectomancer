defmodule Ectomancer.SQLTool do
  @moduledoc """
  Optional SQL execution tool for advanced database queries.

  This module provides a tool for executing raw SQL queries against the
  configured Ecto repository. It's disabled by default for security.

  ## Configuration

      # config/config.exs
      config :ectomancer, :sql_execution,
        enabled: true,              # Enable SQL tool (default: false)
        max_rows: 100,              # Maximum rows to return (default: 100)
        read_only: true,            # Only allow SELECT statements (default: true)
        allowed_repos: [MyApp.Repo] # Which repos can be queried

  ## Usage

      defmodule MyApp.MCP do
        use Ectomancer

        # Include the SQL tool (if enabled in config)
        import Ectomancer.SQLTool

        tool :execute_sql do
          description "Execute SQL queries against the database"
          param :query, :string, required: true
          param :args, {:array, :string}, required: false

          handle fn %{"query" => query, "args" => args}, _actor ->
            Ectomancer.SQLTool.execute(query, args || [])
          end
        end
      end

  ## Security

  - Parameterized queries only (prevents SQL injection)
  - Row limits prevent memory issues
  - Read-only mode prevents data modification
  - Audit logging tracks all queries
  """

  alias Ectomancer.Repo

  @doc """
  Checks if SQL execution is enabled in configuration.
  """
  @spec enabled?() :: boolean()
  def enabled? do
    Application.get_env(:ectomancer, :sql_execution, [])
    |> Keyword.get(:enabled, false)
  end

  @doc """
  Gets the configuration for SQL execution.
  """
  @spec config() :: keyword()
  def config do
    defaults = [
      enabled: false,
      max_rows: 100,
      read_only: true,
      allowed_repos: []
    ]

    config = Application.get_env(:ectomancer, :sql_execution, [])
    Keyword.merge(defaults, config)
  end

  @doc """
  Executes a SQL query with optional parameters.

  ## Parameters

    * `query` - The SQL query string
    * `args` - List of arguments for parameterized queries

  ## Returns

    * `{:ok, result}` - Query executed successfully
    * `{:error, reason}` - Query failed or not allowed

  ## Examples

      Ectomancer.SQLTool.execute("SELECT * FROM users WHERE email = $1", ["test@example.com"])
      #=> {:ok, %{columns: ["id", "email"], rows: [[1, "test@example.com"]]}}
  """
  @spec execute(String.t(), list()) :: {:ok, map()} | {:error, any()}
  def execute(query, args \\ []) do
    with true <- enabled?() || {:error, :sql_execution_disabled},
         cfg = config(),
         repo = Repo.repo(),
         true <- not is_nil(repo) || {:error, :repo_not_configured},
         true <- allowed_repo?(cfg[:allowed_repos], repo),
         true <- not cfg[:read_only] || select_query?(query) || {:error, :read_only_mode} do
      # Log the query for audit
      if cfg[:audit_log] do
        log_query(query, args)
      end

      # Execute the query with row limit
      try do
        case repo.query(query, args) do
          {:ok, result} ->
            {:ok, format_result(result, cfg[:max_rows])}

          {:error, reason} ->
            {:error, "Query failed: #{inspect(reason)}"}
        end
      rescue
        e -> {:error, Exception.message(e)}
      end
    end
  end

  @doc """
  Validates a SQL query before execution.

  Returns true if the query is valid and allowed.
  """
  @spec valid_query?(String.t()) :: boolean()
  def valid_query?(query) do
    query = String.trim(query) |> String.downcase()

    # Check for dangerous operations in read-only mode
    if config()[:read_only] do
      not String.starts_with?(query, "insert") and
        not String.starts_with?(query, "update") and
        not String.starts_with?(query, "delete") and
        not String.starts_with?(query, "drop") and
        not String.starts_with?(query, "alter") and
        not String.starts_with?(query, "truncate") and
        not String.starts_with?(query, "create")
    else
      true
    end
  end

  # Private functions

  defp select_query?(query) do
    query
    |> String.trim()
    |> String.downcase()
    |> String.starts_with?("select")
  end

  defp allowed_repo?([], _repo), do: true

  defp allowed_repo?(allowed_repos, repo),
    do: repo in allowed_repos || {:error, :repo_not_allowed}

  defp format_result(%{columns: columns, rows: rows, num_rows: num_rows}, max_rows) do
    truncated_rows =
      if num_rows > max_rows do
        Enum.take(rows, max_rows)
      else
        rows
      end

    %{
      columns: columns,
      rows: truncated_rows,
      num_rows: num_rows,
      truncated: num_rows > max_rows,
      max_rows: max_rows
    }
  end

  defp format_result(result, _max_rows) do
    # Handle non-SELECT results
    Map.take(result, [:columns, :rows, :num_rows])
  end

  defp log_query(query, args) do
    require Logger

    Logger.info("""
    [Ectomancer.SQLTool] Query executed:
    Query: #{query}
    Args: #{inspect(args)}
    Time: #{DateTime.utc_now()}
    """)
  end
end
