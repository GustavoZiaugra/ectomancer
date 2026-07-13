defmodule Ectomancer.TelemetryTest do
  use ExUnit.Case

  defmodule TestMCP do
    use Ectomancer,
      name: "telemetry-test-mcp",
      version: "1.0.0"

    tool :hello do
      description("Say hello")
      param(:name, :string, required: true)

      handle(fn %{"name" => name}, _actor ->
        {:ok, "Hello, #{name}!"}
      end)
    end

    tool :explode do
      description("Always raises")
      param(:reason, :string)

      handle(fn _params, _actor ->
        raise "boom"
      end)
    end
  end

  alias TestMCP.Tool.Explode
  alias TestMCP.Tool.Hello

  def handle_event(name, measurements, metadata, _config) do
    send(self(), {:telemetry_event, name, measurements, metadata})
  end

  setup do
    handler_id =
      :telemetry.attach_many(
        "ectomancer-telemetry-test",
        [
          [:ectomancer, :tool, :start],
          [:ectomancer, :tool, :stop],
          [:ectomancer, :tool, :exception],
          [:ectomancer, :repo, :start],
          [:ectomancer, :repo, :stop],
          [:ectomancer, :repo, :exception],
          [:ectomancer, :authorization, :denied],
          [:ectomancer, :rate_limit, :exceeded]
        ],
        &__MODULE__.handle_event/4,
        nil
      )

    on_exit(fn -> :telemetry.detach(handler_id) end)

    :ok
  end

  describe "tool events" do
    test "emits start and stop events on successful tool execution" do
      frame = %{assigns: %{ectomancer_actor: nil}}

      {:reply, _response, _frame} = Hello.execute(%{"name" => "Alice"}, frame)

      assert_received {:telemetry_event, [:ectomancer, :tool, :start], measurements, metadata}
      assert Map.has_key?(measurements, :system_time)
      assert metadata[:tool] == "hello"

      assert_received {:telemetry_event, [:ectomancer, :tool, :stop], measurements, metadata}
      assert Map.has_key?(measurements, :duration)
      assert metadata[:tool] == "hello"
    end

    test "emits exception event when tool handler raises" do
      frame = %{assigns: %{ectomancer_actor: nil}}

      result = Explode.execute(%{}, frame)

      assert {:error, _, _} = result

      assert_received {:telemetry_event, [:ectomancer, :tool, :exception], measurements, metadata}

      assert Map.has_key?(measurements, :duration)
      assert metadata[:tool] == "explode"
    end
  end

  describe "repo events" do
    test "emits start and stop events for Repo.list" do
      result = Ectomancer.Repo.list(Ectomancer.TestRepo)

      assert {:error, _} = result

      assert_received {:telemetry_event, [:ectomancer, :repo, :start], measurements, metadata}
      assert Map.has_key?(measurements, :system_time)
      assert metadata[:action] == :list

      assert_received {:telemetry_event, [:ectomancer, :repo, :stop], measurements, metadata}
      assert Map.has_key?(measurements, :duration)
      assert metadata[:action] == :list
    end

    test "emits start and stop events for Repo.get" do
      result = Ectomancer.Repo.get(Ectomancer.TestRepo, %{"id" => 1})

      assert {:error, _} = result

      assert_received {:telemetry_event, [:ectomancer, :repo, :start], _measurements, metadata}
      assert metadata[:action] == :get

      assert_received {:telemetry_event, [:ectomancer, :repo, :stop], _measurements, metadata}
      assert metadata[:action] == :get
    end

    test "emits start and stop events for Repo.create" do
      result = Ectomancer.Repo.create(Ectomancer.TestRepo, %{})

      assert {:error, _} = result

      assert_received {:telemetry_event, [:ectomancer, :repo, :start], _measurements, metadata}
      assert metadata[:action] == :create

      assert_received {:telemetry_event, [:ectomancer, :repo, :stop], _measurements, metadata}
      assert metadata[:action] == :create
    end

    test "emits start and stop events for Repo.update" do
      result = Ectomancer.Repo.update(Ectomancer.TestRepo, %{"id" => 1})

      assert {:error, _} = result

      assert_received {:telemetry_event, [:ectomancer, :repo, :start], _measurements, metadata}
      assert metadata[:action] == :update

      assert_received {:telemetry_event, [:ectomancer, :repo, :stop], _measurements, metadata}
      assert metadata[:action] == :update
    end

    test "emits start and stop events for Repo.destroy" do
      result = Ectomancer.Repo.destroy(Ectomancer.TestRepo, %{"id" => 1})

      assert {:error, _} = result

      assert_received {:telemetry_event, [:ectomancer, :repo, :start], _measurements, metadata}
      assert metadata[:action] == :destroy

      assert_received {:telemetry_event, [:ectomancer, :repo, :stop], _measurements, metadata}
      assert metadata[:action] == :destroy
    end

    test "emits start and stop events for Repo.restore" do
      result = Ectomancer.Repo.restore(Ectomancer.TestRepo, %{"id" => 1})

      assert {:error, _} = result

      assert_received {:telemetry_event, [:ectomancer, :repo, :start], _measurements, metadata}
      assert metadata[:action] == :restore

      assert_received {:telemetry_event, [:ectomancer, :repo, :stop], _measurements, metadata}
      assert metadata[:action] == :restore
    end
  end

  describe "authorization denied event" do
    test "emits event when authorization check fails" do
      handler = fn _actor, _action -> false end

      result = Ectomancer.Authorization.check(%{id: 1}, :list, handler: handler)

      assert {:error, _} = result

      assert_received {:telemetry_event, [:ectomancer, :authorization, :denied], _measurements,
                       metadata}

      assert metadata[:action] == :list
      assert metadata[:actor] == %{id: 1}
    end

    test "emits event for policy module not found" do
      result = Ectomancer.Authorization.check(%{}, :list, handler: NonExistent.Policy)

      assert {:error, _} = result

      assert_received {:telemetry_event, [:ectomancer, :authorization, :denied], _measurements,
                       _metadata}
    end

    test "does not emit event when authorization passes" do
      handler = fn _actor, _action -> true end

      result = Ectomancer.Authorization.check(%{}, :list, handler: handler)

      assert :ok == result

      refute_received {:telemetry_event, [:ectomancer, :authorization, :denied], _, _}
    end
  end

  describe "rate limit exceeded event" do
    test "emits event when rate limit is exceeded" do
      Ectomancer.RateLimiter.reset()

      Ectomancer.RateLimiter.check(max: 1, window_ms: 60_000, key: :telemetry_test)
      result = Ectomancer.RateLimiter.check(max: 1, window_ms: 60_000, key: :telemetry_test)

      assert {:error, :rate_limited, _} = result

      assert_received {:telemetry_event, [:ectomancer, :rate_limit, :exceeded], _measurements,
                       metadata}

      assert metadata[:window_ms] == 60_000
      assert is_binary(metadata[:key])
    end

    test "does not emit event when rate limit passes" do
      Ectomancer.RateLimiter.reset()

      result = Ectomancer.RateLimiter.check(max: 1, window_ms: 60_000, key: :pass_test)

      assert :ok == result

      refute_received {:telemetry_event, [:ectomancer, :rate_limit, :exceeded], _, _}
    end
  end

  describe "telemetry disabled" do
    test "does not emit events when telemetry is disabled via config" do
      Application.put_env(:ectomancer, :telemetry, false)

      handler = fn _actor, _action -> false end
      Ectomancer.Authorization.check(%{}, :list, handler: handler)

      refute_received {:telemetry_event, [:ectomancer, :authorization, :denied], _, _}

      Application.delete_env(:ectomancer, :telemetry)
    end
  end
end
