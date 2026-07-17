if Code.ensure_loaded?(Oban) do
  defmodule Ectomancer.ObanBridge.Queries do
    @moduledoc false

    import Ecto.Query

    def list_queues do
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

        formatted =
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

        {:ok, %{queues: formatted}}
      rescue
        e ->
          {:error, "Failed to list queues: #{Exception.message(e)}"}
      end
    end

    def get_queue_depth(queue_name) when is_binary(queue_name) do
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

    def list_stuck_jobs(filters \\ %{}) do
      _ = repo()

      try do
        query =
          Oban.Job
          |> where([j], j.state == "executing")

        query =
          Enum.reduce(filters, query, fn
            {:queue, queue}, q -> where(q, [j], j.queue == ^queue)
            {:worker, worker}, q -> where(q, [j], j.worker == ^worker)
            {:min_age_minutes, minutes}, q ->
              cutoff = DateTime.utc_now() |> DateTime.add(-minutes, :minute)
              where(q, [j], j.attempted_at < ^cutoff)
            _, q -> q
          end)

        query =
          query
          |> order_by([j], desc: j.attempted_at)
          |> limit(^Map.get(filters, :limit, 100))

        jobs = repo_all(query)

        formatted =
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

        {:ok, %{jobs: formatted, count: length(formatted)}}
      rescue
        e ->
          {:error, "Failed to list stuck jobs: #{Exception.message(e)}"}
      end
    end

    def retry_job(job_id) when is_integer(job_id) do
      _ = repo()

      try do
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

    def cancel_job(job_id) when is_integer(job_id) do
      _ = repo()

      try do
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

    def repo do
      Application.get_env(:ectomancer, :repo) ||
        raise ArgumentError,
              "Ectomancer repo not configured. Set config :ectomancer, :repo, YourApp.Repo"
    end

    defp repo_all(query), do: repo().all(query)
    defp repo_one(query), do: repo().one(query)
    defp repo_update_all(query, opts), do: repo().update_all(query, opts)
    defp repo_delete_all(query), do: repo().delete_all(query)
  end
else
  defmodule Ectomancer.ObanBridge.Queries do
    @moduledoc false
  end
end
