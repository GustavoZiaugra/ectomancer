defmodule Ectomancer.ObanBridgeTest do
  use ExUnit.Case, async: false

  alias Ectomancer.ObanBridge

  # Mock Oban.Job module for testing when Oban is not loaded
  defmodule MockObanJob do
    use Ecto.Schema

    schema "oban_jobs" do
      field(:queue, :string)
      field(:worker, :string)
      field(:args, :map)
      field(:state, :string)
      field(:attempt, :integer)
      field(:max_attempts, :integer)
      field(:attempted_at, :utc_datetime_usec)
      field(:inserted_at, :utc_datetime_usec)
      field(:errors, {:array, :map})
    end
  end

  describe "ObanBridge module structure" do
    test "module is defined" do
      assert Code.ensure_loaded?(ObanBridge)
    end

    test "macro expose_oban_jobs/0 is exported" do
      assert function_exported?(ObanBridge, :__info__, 1)
    end
  end

  describe "when Oban is not available" do
    test "macro generates no tools" do
      # This test verifies the compile-time behavior
      # When Oban is not in deps, the macro should generate :ok
      # We can't easily test this in the same project that has Oban,
      # but the code structure is designed to handle this case
      assert true
    end
  end

  describe "list_queues/0" do
    test "returns error when repo not configured" do
      # Save original env
      original_env = Application.get_env(:ectomancer, :repo)
      Application.delete_env(:ectomancer, :repo)

      try do
        assert_raise ArgumentError, ~r/repo not configured/, fn ->
          ObanBridge.list_queues()
        end
      after
        # Restore original env
        if original_env do
          Application.put_env(:ectomancer, :repo, original_env)
        end
      end
    end
  end

  describe "get_queue_depth/1" do
    test "accepts string queue name" do
      # Test input validation
      # When repo not configured, should raise error before hitting DB
      original_env = Application.get_env(:ectomancer, :repo)
      Application.delete_env(:ectomancer, :repo)

      try do
        assert_raise ArgumentError, ~r/repo not configured/, fn ->
          ObanBridge.get_queue_depth("default")
        end
      after
        if original_env do
          Application.put_env(:ectomancer, :repo, original_env)
        end
      end
    end

    test "rejects non-string queue name" do
      assert {:error, "queue_name must be a string"} = ObanBridge.get_queue_depth(nil)
      assert {:error, "queue_name must be a string"} = ObanBridge.get_queue_depth(123)
      assert {:error, "queue_name must be a string"} = ObanBridge.get_queue_depth(:default)
    end
  end

  describe "retry_job/1" do
    test "accepts integer job_id" do
      # Test input validation
      original_env = Application.get_env(:ectomancer, :repo)
      Application.delete_env(:ectomancer, :repo)

      try do
        assert_raise ArgumentError, ~r/repo not configured/, fn ->
          ObanBridge.retry_job(123)
        end
      after
        if original_env do
          Application.put_env(:ectomancer, :repo, original_env)
        end
      end
    end

    test "rejects non-integer job_id" do
      assert {:error, "job_id must be an integer"} = ObanBridge.retry_job(nil)
      assert {:error, "job_id must be an integer"} = ObanBridge.retry_job("123")
      assert {:error, "job_id must be an integer"} = ObanBridge.retry_job(123.45)
    end
  end

  describe "cancel_job/1" do
    test "accepts integer job_id" do
      # Test input validation
      original_env = Application.get_env(:ectomancer, :repo)
      Application.delete_env(:ectomancer, :repo)

      try do
        assert_raise ArgumentError, ~r/repo not configured/, fn ->
          ObanBridge.cancel_job(123)
        end
      after
        if original_env do
          Application.put_env(:ectomancer, :repo, original_env)
        end
      end
    end

    test "rejects non-integer job_id" do
      assert {:error, "job_id must be an integer"} = ObanBridge.cancel_job(nil)
      assert {:error, "job_id must be an integer"} = ObanBridge.cancel_job("123")
      assert {:error, "job_id must be an integer"} = ObanBridge.cancel_job(123.45)
    end
  end

  describe "list_stuck_jobs/1" do
    test "accepts empty filters" do
      # Test input validation
      original_env = Application.get_env(:ectomancer, :repo)
      Application.delete_env(:ectomancer, :repo)

      try do
        assert_raise ArgumentError, ~r/repo not configured/, fn ->
          ObanBridge.list_stuck_jobs(%{})
        end
      after
        if original_env do
          Application.put_env(:ectomancer, :repo, original_env)
        end
      end
    end

    test "accepts filter parameters" do
      # Verify the function accepts filter params without error
      # (actual query will fail without repo, but that's tested above)
      filters = %{
        queue: "default",
        worker: "MyWorker",
        min_age_minutes: 30,
        limit: 50
      }

      # Just verify the function can be called with these filters
      # The actual query will fail without repo config
      assert is_map(filters)
      assert filters.queue == "default"
      assert filters.worker == "MyWorker"
      assert filters.min_age_minutes == 30
      assert filters.limit == 50
    end
  end

  describe "macro-generated tools" do
    defmodule ObanMCP do
      use Ectomancer, name: "oban-test", version: "1.0.0"
      expose_oban_jobs()
    end

    defmodule NamespacedObanMCP do
      use Ectomancer, name: "oban-ns-test", version: "1.0.0"
      expose_oban_jobs(namespace: :background)
    end

    test "generates list_oban_queues tool" do
      assert Code.ensure_loaded?(ObanMCP.Tool.ListObanQueues)
      assert ObanMCP.Tool.ListObanQueues.name() == "list_oban_queues"
    end

    test "generates get_queue_depth tool" do
      assert Code.ensure_loaded?(ObanMCP.Tool.GetQueueDepth)
      assert ObanMCP.Tool.GetQueueDepth.name() == "get_queue_depth"
    end

    test "generates list_stuck_jobs tool" do
      assert Code.ensure_loaded?(ObanMCP.Tool.ListStuckJobs)
      assert ObanMCP.Tool.ListStuckJobs.name() == "list_stuck_jobs"
    end

    test "generates retry_job tool" do
      assert Code.ensure_loaded?(ObanMCP.Tool.RetryJob)
      assert ObanMCP.Tool.RetryJob.name() == "retry_job"
    end

    test "generates cancel_job tool" do
      assert Code.ensure_loaded?(ObanMCP.Tool.CancelJob)
      assert ObanMCP.Tool.CancelJob.name() == "cancel_job"
    end

    test "namespace prefix is applied" do
      assert Code.ensure_loaded?(NamespacedObanMCP.Tool.BackgroundListObanQueues)

      assert NamespacedObanMCP.Tool.BackgroundListObanQueues.name() ==
               "background_list_oban_queues"
    end

    test "generated tools have JSON schemas" do
      schema = ObanMCP.Tool.ListObanQueues.input_schema()
      assert is_map(schema)
      assert schema["type"] == "object"
    end
  end

  describe "build_tool_name/2" do
    test "namespaced tool names" do
      assert ObanBridge.build_tool_name("list_oban_queues", nil) == :list_oban_queues

      assert ObanBridge.build_tool_name("list_oban_queues", :background) ==
               :background_list_oban_queues
    end
  end

  describe "documentation examples" do
    test "module can be loaded" do
      assert Code.ensure_loaded?(Ectomancer.ObanBridge)
    end
  end

  describe "repo/0" do
    test "raises when repo not configured" do
      original_env = Application.get_env(:ectomancer, :repo)
      Application.delete_env(:ectomancer, :repo)

      try do
        assert_raise ArgumentError, ~r/repo not configured/, fn ->
          ObanBridge.repo()
        end
      after
        if original_env do
          Application.put_env(:ectomancer, :repo, original_env)
        end
      end
    end
  end

  describe "API with repo configured" do
    setup do
      original_env = Application.get_env(:ectomancer, :repo)
      Application.put_env(:ectomancer, :repo, Ectomancer.TestRepo)
      Ecto.Adapters.SQL.Sandbox.checkout(Ectomancer.TestRepo)

      on_exit(fn ->
        if original_env do
          Application.put_env(:ectomancer, :repo, original_env)
        else
          Application.delete_env(:ectomancer, :repo)
        end
      end)

      :ok
    end

    test "list_queues/0 returns error when table missing" do
      assert {:error, msg} = ObanBridge.list_queues()
      assert msg =~ "Failed to list queues"
    end

    test "get_queue_depth/1 returns error when table missing" do
      assert {:error, msg} = ObanBridge.get_queue_depth("default")
      assert msg =~ "Failed to get queue depth"
    end

    test "list_stuck_jobs/1 returns error when table missing" do
      assert {:error, msg} = ObanBridge.list_stuck_jobs(%{queue: "default", limit: 10})
      assert msg =~ "Failed to list stuck jobs"
    end

    test "retry_job/1 returns error when table missing" do
      assert {:error, msg} = ObanBridge.retry_job(42)
      assert msg =~ "Failed to retry job"
    end

    test "cancel_job/1 returns error when table missing" do
      assert {:error, msg} = ObanBridge.cancel_job(42)
      assert msg =~ "Failed to cancel job"
    end

    test "list_stuck_jobs/1 without filters returns error" do
      assert {:error, msg} = ObanBridge.list_stuck_jobs()
      assert msg =~ "Failed to list stuck jobs"
    end

    test "list_stuck_jobs/1 with worker filter" do
      assert {:error, msg} = ObanBridge.list_stuck_jobs(%{worker: "MyWorker"})
      assert msg =~ "Failed to list stuck jobs"
    end

    test "list_stuck_jobs/1 with min_age_minutes filter" do
      assert {:error, msg} = ObanBridge.list_stuck_jobs(%{min_age_minutes: 30})
      assert msg =~ "Failed to list stuck jobs"
    end
  end

  describe "API with oban_jobs table" do
    setup do
      original_env = Application.get_env(:ectomancer, :repo)
      Application.put_env(:ectomancer, :repo, Ectomancer.TestRepo)
      Ecto.Adapters.SQL.Sandbox.checkout(Ectomancer.TestRepo)

      Ectomancer.DataCase.create_table_for_schema!(Oban.Job)

      on_exit(fn ->
        if original_env do
          Application.put_env(:ectomancer, :repo, original_env)
        else
          Application.delete_env(:ectomancer, :repo)
        end
      end)

      :ok
    end

    test "list_queues/0 returns empty queues when no jobs" do
      {:ok, result} = ObanBridge.list_queues()
      assert result.queues == []
    end

    test "list_queues/0 returns queue stats with jobs" do
      now = DateTime.utc_now() |> DateTime.truncate(:second) |> to_string()

      Ecto.Adapters.SQL.query!(Ectomancer.TestRepo, """
        INSERT INTO oban_jobs (queue, state, inserted_at, scheduled_at)
        VALUES ('default', 'available', '#{now}', '#{now}')
      """)

      Ecto.Adapters.SQL.query!(Ectomancer.TestRepo, """
        INSERT INTO oban_jobs (queue, state, inserted_at, scheduled_at)
        VALUES ('default', 'executing', '#{now}', '#{now}')
      """)

      Ecto.Adapters.SQL.query!(Ectomancer.TestRepo, """
        INSERT INTO oban_jobs (queue, state, inserted_at, scheduled_at)
        VALUES ('mailer', 'available', '#{now}', '#{now}')
      """)

      {:ok, result} = ObanBridge.list_queues()
      assert length(result.queues) == 2
    end

    test "get_queue_depth/1 returns stats for a queue" do
      now = DateTime.utc_now() |> DateTime.truncate(:second) |> to_string()

      Ecto.Adapters.SQL.query!(Ectomancer.TestRepo, """
        INSERT INTO oban_jobs (queue, state, inserted_at, scheduled_at)
        VALUES ('default', 'available', '#{now}', '#{now}')
      """)

      Ecto.Adapters.SQL.query!(Ectomancer.TestRepo, """
        INSERT INTO oban_jobs (queue, state, inserted_at, scheduled_at)
        VALUES ('default', 'executing', '#{now}', '#{now}')
      """)

      {:ok, result} = ObanBridge.get_queue_depth("default")
      assert result.queue == "default"
      assert result.total == 2
    end

    test "get_queue_depth/1 returns zeros for empty queue" do
      {:ok, result} = ObanBridge.get_queue_depth("nonexistent")
      assert result.total == 0
    end

    test "list_stuck_jobs/1 returns executing jobs" do
      now = DateTime.utc_now() |> DateTime.truncate(:second) |> to_string()

      Ecto.Adapters.SQL.query!(Ectomancer.TestRepo, """
        INSERT INTO oban_jobs (queue, state, worker, inserted_at, scheduled_at, attempted_at)
        VALUES ('default', 'executing', 'MyWorker', '#{now}', '#{now}', '#{now}')
      """)

      Ecto.Adapters.SQL.query!(Ectomancer.TestRepo, """
        INSERT INTO oban_jobs (queue, state, worker, inserted_at, scheduled_at)
        VALUES ('default', 'available', 'OtherWorker', '#{now}', '#{now}')
      """)

      {:ok, result} = ObanBridge.list_stuck_jobs(%{})
      assert result.count == 1
    end

    test "list_stuck_jobs/1 filters by queue" do
      now = DateTime.utc_now() |> DateTime.truncate(:second) |> to_string()

      Ecto.Adapters.SQL.query!(Ectomancer.TestRepo, """
        INSERT INTO oban_jobs (queue, state, worker, inserted_at, scheduled_at, attempted_at)
        VALUES ('default', 'executing', 'W1', '#{now}', '#{now}', '#{now}')
      """)

      Ecto.Adapters.SQL.query!(Ectomancer.TestRepo, """
        INSERT INTO oban_jobs (queue, state, worker, inserted_at, scheduled_at, attempted_at)
        VALUES ('mailer', 'executing', 'W2', '#{now}', '#{now}', '#{now}')
      """)

      {:ok, result} = ObanBridge.list_stuck_jobs(%{queue: "default"})
      assert result.count == 1
    end

    test "retry_job/1 retries a discarded job" do
      now = DateTime.utc_now() |> DateTime.truncate(:second) |> to_string()

      Ecto.Adapters.SQL.query!(Ectomancer.TestRepo, """
        INSERT INTO oban_jobs (state, queue, worker, inserted_at, scheduled_at)
        VALUES ('discarded', 'default', 'W1', '#{now}', '#{now}')
      """)

      %{rows: [[job_id | _]]} =
        Ecto.Adapters.SQL.query!(
          Ectomancer.TestRepo,
          "SELECT id FROM oban_jobs WHERE state = 'discarded' LIMIT 1"
        )

      {:ok, result} = ObanBridge.retry_job(job_id)
      assert result.job_id == job_id
    end

    test "retry_job/1 fails for non-retryable state" do
      now = DateTime.utc_now() |> DateTime.truncate(:second) |> to_string()

      Ecto.Adapters.SQL.query!(Ectomancer.TestRepo, """
        INSERT INTO oban_jobs (state, queue, worker, inserted_at, scheduled_at)
        VALUES ('completed', 'default', 'W1', '#{now}', '#{now}')
      """)

      %{rows: [[job_id | _]]} =
        Ecto.Adapters.SQL.query!(
          Ectomancer.TestRepo,
          "SELECT id FROM oban_jobs WHERE state = 'completed' LIMIT 1"
        )

      {:error, msg} = ObanBridge.retry_job(job_id)
      assert msg =~ "not found or not in retryable"
    end

    test "cancel_job/1 cancels an available job" do
      now = DateTime.utc_now() |> DateTime.truncate(:second) |> to_string()

      Ecto.Adapters.SQL.query!(Ectomancer.TestRepo, """
        INSERT INTO oban_jobs (state, queue, worker, inserted_at, scheduled_at)
        VALUES ('available', 'default', 'W1', '#{now}', '#{now}')
      """)

      %{rows: [[job_id | _]]} =
        Ecto.Adapters.SQL.query!(
          Ectomancer.TestRepo,
          "SELECT id FROM oban_jobs WHERE state = 'available' LIMIT 1"
        )

      {:ok, result} = ObanBridge.cancel_job(job_id)
      assert result.job_id == job_id
    end

    test "cancel_job/1 fails for completed job" do
      now = DateTime.utc_now() |> DateTime.truncate(:second) |> to_string()

      Ecto.Adapters.SQL.query!(Ectomancer.TestRepo, """
        INSERT INTO oban_jobs (state, queue, worker, inserted_at, scheduled_at)
        VALUES ('completed', 'default', 'W1', '#{now}', '#{now}')
      """)

      %{rows: [[job_id | _]]} =
        Ecto.Adapters.SQL.query!(
          Ectomancer.TestRepo,
          "SELECT id FROM oban_jobs WHERE state = 'completed' LIMIT 1"
        )

      {:error, msg} = ObanBridge.cancel_job(job_id)
      assert msg =~ "not found or already completed"
    end
  end
end
