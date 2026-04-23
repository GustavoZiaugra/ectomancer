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
        generate_oban_tools(namespace)
      else
        # Oban not available, generate nothing
        quote do
          :ok
        end
      end
    end

    # Generate all Oban management tools
    defp generate_oban_tools(namespace) do
      tools = [
        generate_list_queues_tool(namespace),
        generate_get_queue_depth_tool(namespace),
        generate_list_stuck_jobs_tool(namespace),
        generate_retry_job_tool(namespace),
        generate_cancel_job_tool(namespace)
      ]

      quote do
        (unquote_splicing(tools))
      end
    end

    defp build_tool_name(base_name, namespace) do
      if namespace do
        String.to_atom("#{namespace}_#{base_name}")
      else
        String.to_atom(base_name)
      end
    end

    # Tool 1: list_oban_queues
    defp generate_list_queues_tool(namespace) do
      tool_name = build_tool_name("list_oban_queues", namespace)

      quote do
        tool unquote(tool_name) do
          description("List all Oban queues with job statistics")
          authorize(:none)

          handle(fn _params, _actor ->
            Ectomancer.ObanBridge.list_queues()
          end)
        end
      end
    end

    # Tool 2: get_queue_depth
    defp generate_get_queue_depth_tool(namespace) do
      tool_name = build_tool_name("get_queue_depth", namespace)

      quote do
        tool unquote(tool_name) do
          description("Get job count for a specific Oban queue")
          param(:queue_name, :string, required: true)
          authorize(:none)

          handle(fn params, _actor ->
            queue_name = params["queue_name"] || params[:queue_name]
            Ectomancer.ObanBridge.get_queue_depth(queue_name)
          end)
        end
      end
    end

    # Tool 3: list_stuck_jobs
    defp generate_list_stuck_jobs_tool(namespace) do
      tool_name = build_tool_name("list_stuck_jobs", namespace)

      quote do
        tool unquote(tool_name) do
          description("List executing/stuck Oban jobs with optional filters")
          param(:queue, :string)
          param(:worker, :string)
          param(:min_age_minutes, :integer)
          param(:limit, :integer)
          authorize(:none)

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

            Ectomancer.ObanBridge.list_stuck_jobs(filters)
          end)
        end
      end
    end

    # Tool 4: retry_job
    defp generate_retry_job_tool(namespace) do
      tool_name = build_tool_name("retry_job", namespace)

      quote do
        tool unquote(tool_name) do
          description("Retry a failed or discarded Oban job by ID")
          param(:job_id, :integer, required: true)
          authorize(:none)

          handle(fn params, _actor ->
            job_id = params["job_id"] || params[:job_id]
            Ectomancer.ObanBridge.retry_job(job_id)
          end)
        end
      end
    end

    # Tool 5: cancel_job
    defp generate_cancel_job_tool(namespace) do
      tool_name = build_tool_name("cancel_job", namespace)

      quote do
        tool unquote(tool_name) do
          description("Cancel or delete an Oban job by ID")
          param(:job_id, :integer, required: true)
          authorize(:none)

          handle(fn params, _actor ->
            job_id = params["job_id"] || params[:job_id]
            Ectomancer.ObanBridge.cancel_job(job_id)
          end)
        end
      end
    end

    # Public API implementations

    @doc false
    def list_queues do
      import Ecto.Query

      # Check repo is configured before attempting query
      _ = repo()

      try do
        queues =
          Oban.Job
          |> select(
            [j],
            {j.queue, fragment("COUNT(*)"),
             fragment("SUM(CASE WHEN state = 'executing' THEN 1 ELSE 0 END)"),
             fragment("SUM(CASE WHEN state = 'available' THEN 1 ELSE 0 END)"),
             fragment("SUM(CASE WHEN state = 'retryable' THEN 1 ELSE 0 END)"),
             fragment("SUM(CASE WHEN state = 'discarded' THEN 1 ELSE 0 END)")}
          )
          |> group_by([j], j.queue)
          |> order_by([j], j.queue)
          |> repo_all()

        formatted_queues =
          Enum.map(queues, fn {queue, total, executing, available, retryable, discarded} ->
            %{
              queue: queue,
              total: total || 0,
              executing: executing || 0,
              available: available || 0,
              retryable: retryable || 0,
              discarded: discarded || 0
            }
          end)

        {:ok, %{queues: formatted_queues}}
      rescue
        e ->
          {:error, "Failed to list queues: #{Exception.message(e)}"}
      end
    end

    @doc false
    def get_queue_depth(queue_name) when is_binary(queue_name) do
      import Ecto.Query

      # Check repo is configured before attempting query
      _ = repo()

      try do
        counts =
          Oban.Job
          |> where([j], j.queue == ^queue_name)
          |> select([j], {
            fragment("COUNT(*)"),
            fragment("SUM(CASE WHEN state = 'executing' THEN 1 ELSE 0 END)"),
            fragment("SUM(CASE WHEN state = 'available' THEN 1 ELSE 0 END)"),
            fragment("SUM(CASE WHEN state = 'retryable' THEN 1 ELSE 0 END)"),
            fragment("SUM(CASE WHEN state = 'discarded' THEN 1 ELSE 0 END)")
          })
          |> repo_one()

        case counts do
          nil ->
            {:ok,
             %{
               queue: queue_name,
               total: 0,
               executing: 0,
               available: 0,
               retryable: 0,
               discarded: 0
             }}

          {total, executing, available, retryable, discarded} ->
            {:ok,
             %{
               queue: queue_name,
               total: total || 0,
               executing: executing || 0,
               available: available || 0,
               retryable: retryable || 0,
               discarded: discarded || 0
             }}
        end
      rescue
        e ->
          {:error, "Failed to get queue depth: #{Exception.message(e)}"}
      end
    end

    def get_queue_depth(_), do: {:error, "queue_name must be a string"}

    @doc false
    def list_stuck_jobs(filters \\ %{}) do
      import Ecto.Query

      # Check repo is configured before attempting query
      _ = repo()

      try do
        query =
          Oban.Job
          |> where([j], j.state == "executing")

        # Apply optional filters
        query =
          Enum.reduce(filters, query, fn
            {:queue, queue}, q ->
              where(q, [j], j.queue == ^queue)

            {:worker, worker}, q ->
              where(q, [j], j.worker == ^worker)

            {:min_age_minutes, minutes}, q ->
              cutoff = DateTime.utc_now() |> DateTime.add(-minutes, :minute)
              where(q, [j], j.attempted_at < ^cutoff)

            _, q ->
              q
          end)

        query =
          query
          |> order_by([j], desc: j.attempted_at)
          |> limit(^Map.get(filters, :limit, 100))

        jobs = repo_all(query)

        formatted_jobs =
          Enum.map(jobs, fn job ->
            %{
              id: job.id,
              queue: job.queue,
              worker: job.worker,
              args: job.args,
              state: job.state,
              attempt: job.attempt,
              max_attempts: job.max_attempts,
              attempted_at: job.attempted_at,
              inserted_at: job.inserted_at,
              errors: job.errors
            }
          end)

        {:ok, %{jobs: formatted_jobs, count: length(formatted_jobs)}}
      rescue
        e ->
          {:error, "Failed to list stuck jobs: #{Exception.message(e)}"}
      end
    end

    @doc false
    def retry_job(job_id) when is_integer(job_id) do
      import Ecto.Query

      # Check repo is configured before attempting query
      _ = repo()

      try do
        # Update the job to be available again
        {count, _} =
          Oban.Job
          |> where([j], j.id == ^job_id)
          |> where([j], j.state in ["retryable", "discarded"])
          |> repo_update_all(set: [state: "available", scheduled_at: DateTime.utc_now()])

        if count > 0 do
          {:ok, %{message: "Job #{job_id} scheduled for retry", job_id: job_id}}
        else
          {:error, "Job #{job_id} not found or not in retryable/discarded state"}
        end
      rescue
        e ->
          {:error, "Failed to retry job: #{Exception.message(e)}"}
      end
    end

    def retry_job(_), do: {:error, "job_id must be an integer"}

    @doc false
    def cancel_job(job_id) when is_integer(job_id) do
      import Ecto.Query

      # Check repo is configured before attempting query
      _ = repo()

      try do
        # Cancel the job if it's not already completed
        {count, _} =
          Oban.Job
          |> where([j], j.id == ^job_id)
          |> where([j], j.state != "completed")
          |> repo_delete_all()

        if count > 0 do
          {:ok, %{message: "Job #{job_id} cancelled", job_id: job_id}}
        else
          {:error, "Job #{job_id} not found or already completed"}
        end
      rescue
        e ->
          {:error, "Failed to cancel job: #{Exception.message(e)}"}
      end
    end

    def cancel_job(_), do: {:error, "job_id must be an integer"}

    # Helper functions to work with configured repo

    defp repo do
      Application.get_env(:ectomancer, :repo) ||
        raise ArgumentError,
              "Ectomancer repo not configured. Set config :ectomancer, :repo, YourApp.Repo"
    end

    defp repo_all(query) do
      repo().all(query)
    end

    defp repo_one(query) do
      repo().one(query)
    end

    defp repo_update_all(query, opts) do
      repo().update_all(query, opts)
    end

    defp repo_delete_all(query) do
      repo().delete_all(query)
    end
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
