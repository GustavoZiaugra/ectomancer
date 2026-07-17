if Code.ensure_loaded?(Oban) do
  defmodule Ectomancer.ObanBridge do
    @moduledoc """
    Oban integration for Ectomancer.

    This module provides the `expose_oban_jobs/0` and `expose_oban_jobs/1` macros
    that automatically generate MCP tools for managing Oban job queues.

    ## Usage

        defmodule MyApp.MCP do
          use Ectomancer

          # Expose all Oban job management tools
          expose_oban_jobs

          # Or with namespace prefix
          expose_oban_jobs(namespace: :background)
          # Generates: background_list_oban_queues, etc.
        end

    ## Generated Tools

    When Oban is available in the parent application, this macro generates:

      * `list_oban_queues` - List all configured queues with job statistics
      * `get_queue_depth` - Get job count for a specific queue
      * `list_stuck_jobs` - List executing jobs (optionally filterable)
      * `retry_job` - Retry a job by ID
      * `cancel_job` - Cancel/delete a job by ID

    ## Optional Dependency

    Oban is an optional dependency. If Oban is not in the application's
    dependencies, the macro will generate no tools (silently).

    ## Configuration

    The tools query Oban.Job directly and require:

      * An Ecto repo configured in the parent application
      * Oban tables migrated in the database
      * Oban started in the application supervision tree

    ## Authorization

    By default, Oban tools are public (no authorization). You can add
    authorization by wrapping the macro call or by implementing custom
    authorization at the MCP module level.
    """

    alias Ectomancer.ObanBridge.Queries

    @doc """
    Exposes Oban job management tools.

    ## Options

      * `:namespace` - Prefix tool names with namespace (e.g., `:background` → `background_list_oban_queues`)

    ## Examples

        expose_oban_jobs
        # Generates: list_oban_queues, get_queue_depth, list_stuck_jobs, retry_job, cancel_job

        expose_oban_jobs(namespace: :jobs)
        # Generates: jobs_list_oban_queues, jobs_get_queue_depth, etc.
    """
    defmacro expose_oban_jobs(opts \\ []) do
      if Code.ensure_loaded?(Oban) do
        namespace = Keyword.get(opts, :namespace)

        global_auth_raw = Ectomancer.fetch_global_auth(__CALLER__.module)

        auth_handler =
          if Keyword.has_key?(opts, :authorize) do
            Ectomancer.Authorization.parse_handler_for_global(opts[:authorize])
          else
            Ectomancer.Authorization.parse_handler_for_global(global_auth_raw)
          end

        generate_oban_tools(namespace, auth_handler)
      else
        # Oban not available, generate nothing
        quote do
          :ok
        end
      end
    end

    # Generate all Oban management tools
    defp generate_oban_tools(namespace, auth_handler) do
      tools = [
        generate_list_queues_tool(namespace, auth_handler),
        generate_get_queue_depth_tool(namespace, auth_handler),
        generate_list_stuck_jobs_tool(namespace, auth_handler),
        generate_retry_job_tool(namespace, auth_handler),
        generate_cancel_job_tool(namespace, auth_handler)
      ]

      quote do
        (unquote_splicing(tools))
      end
    end

    @doc false
    def build_tool_name(base_name, namespace) do
      if namespace do
        String.to_atom("#{namespace}_#{base_name}")
      else
        String.to_atom(base_name)
      end
    end

    @doc false
    def oban_authorize_call(nil), do: Ectomancer.Authorization.authorize_to_ast(nil)

    def oban_authorize_call(handler) do
      Ectomancer.Authorization.authorize_to_ast(handler)
    end

    # Tool 1: list_oban_queues
    defp generate_list_queues_tool(namespace, auth_handler) do
      tool_name = build_tool_name("list_oban_queues", namespace)

      quote do
        tool unquote(tool_name) do
          description("List all Oban queues with job statistics")
          unquote(oban_authorize_call(auth_handler))

          handle(fn _params, _actor ->
            Queries.list_queues()
          end)
        end
      end
    end

    # Tool 2: get_queue_depth
    defp generate_get_queue_depth_tool(namespace, auth_handler) do
      tool_name = build_tool_name("get_queue_depth", namespace)

      quote do
        tool unquote(tool_name) do
          description("Get job count for a specific Oban queue")
          param(:queue_name, :string, required: true)
          unquote(oban_authorize_call(auth_handler))

          handle(fn params, _actor ->
            queue_name = params["queue_name"] || params[:queue_name]
            Queries.get_queue_depth(queue_name)
          end)
        end
      end
    end

    # Tool 3: list_stuck_jobs
    defp generate_list_stuck_jobs_tool(namespace, auth_handler) do
      tool_name = build_tool_name("list_stuck_jobs", namespace)

      quote do
        tool unquote(tool_name) do
          description("List executing/stuck Oban jobs with optional filters")
          param(:queue, :string)
          param(:worker, :string)
          param(:min_age_minutes, :integer)
          param(:limit, :integer)
          unquote(oban_authorize_call(auth_handler))

          handle(fn params, _actor ->
            filters =
              %{
                queue: params["queue"] || params[:queue],
                worker: params["worker"] || params[:worker],
                min_age_minutes: params["min_age_minutes"] || params[:min_age_minutes],
                limit: params["limit"] || params[:limit]
              }
              |> Enum.reject(fn {_k, v} -> is_nil(v) end)
              |> Enum.into(%{})

            Queries.list_stuck_jobs(filters)
          end)
        end
      end
    end

    # Tool 4: retry_job
    defp generate_retry_job_tool(namespace, auth_handler) do
      tool_name = build_tool_name("retry_job", namespace)

      quote do
        tool unquote(tool_name) do
          description("Retry a failed or discarded Oban job by ID")
          param(:job_id, :integer, required: true)
          unquote(oban_authorize_call(auth_handler))

          handle(fn params, _actor ->
            job_id = params["job_id"] || params[:job_id]
            Queries.retry_job(job_id)
          end)
        end
      end
    end

    # Tool 5: cancel_job
    defp generate_cancel_job_tool(namespace, auth_handler) do
      tool_name = build_tool_name("cancel_job", namespace)

      quote do
        tool unquote(tool_name) do
          description("Cancel or delete an Oban job by ID")
          param(:job_id, :integer, required: true)
          unquote(oban_authorize_call(auth_handler))

          handle(fn params, _actor ->
            job_id = params["job_id"] || params[:job_id]
            Queries.cancel_job(job_id)
          end)
        end
      end
    end

    @doc false
    defdelegate list_queues(), to: Ectomancer.ObanBridge.Queries
    @doc false
    def get_queue_depth(queue_name) when is_binary(queue_name),
      do: Queries.get_queue_depth(queue_name)

    @doc false
    def get_queue_depth(other),
      do: Queries.get_queue_depth(other)

    @doc false
    def list_stuck_jobs, do: Queries.list_stuck_jobs()
    @doc false
    defdelegate list_stuck_jobs(filters), to: Ectomancer.ObanBridge.Queries
    @doc false
    def retry_job(job_id) when is_integer(job_id),
      do: Queries.retry_job(job_id)

    @doc false
    def retry_job(other),
      do: Queries.retry_job(other)

    @doc false
    def cancel_job(job_id) when is_integer(job_id),
      do: Queries.cancel_job(job_id)

    @doc false
    def cancel_job(other),
      do: Queries.cancel_job(other)

    @doc false
    def repo, do: Queries.repo()
  end
else
  defmodule Ectomancer.ObanBridge do
    @moduledoc false

    defmacro expose_oban_jobs(_opts \\ []) do
      quote do
        :ok
      end
    end
  end
end
