defmodule Ectomancer.RateLimiterTest do
  use ExUnit.Case, async: true

  setup do
    Ectomancer.RateLimiter.reset()
    :ok
  end

  describe "init/0" do
    test "creates ETS table on first call" do
      Ectomancer.RateLimiter.reset()
      assert :ets.info(:ectomancer_rate_limit) == :undefined

      Ectomancer.RateLimiter.init()
      assert :ets.info(:ectomancer_rate_limit) != :undefined
    end

    test "is idempotent" do
      Ectomancer.RateLimiter.init()
      Ectomancer.RateLimiter.init()
      assert :ets.info(:ectomancer_rate_limit) != :undefined
    end
  end

  describe "check/1" do
    test "allows requests up to max in a burst" do
      # 3 max, 10s window = 0.3 tokens/sec
      assert :ok = Ectomancer.RateLimiter.check(max: 3, window_ms: 10_000, key: :burst_test)

      assert :ok = Ectomancer.RateLimiter.check(max: 3, window_ms: 10_000, key: :burst_test)

      assert :ok = Ectomancer.RateLimiter.check(max: 3, window_ms: 10_000, key: :burst_test)

      # Fourth request should be rate limited
      assert {:error, :rate_limited, retry_after} =
               Ectomancer.RateLimiter.check(max: 3, window_ms: 10_000, key: :burst_test)

      assert retry_after > 0
    end

    test "refills tokens over time" do
      max = 2
      window_ms = 2_000  # 2s window = 1 token/sec

      # Consume all tokens
      Ectomancer.RateLimiter.check(max: max, window_ms: window_ms, key: :refill_test)
      Ectomancer.RateLimiter.check(max: max, window_ms: window_ms, key: :refill_test)

      # Should be rate limited
      assert {:error, :rate_limited, _} =
               Ectomancer.RateLimiter.check(max: max, window_ms: window_ms, key: :refill_test)

      # Wait for partial refill (>1 token/sec means ~2 tokens in 1500ms)
      Process.sleep(1500)

      # Should be allowed again (at least 1 token refilled)
      assert :ok =
               Ectomancer.RateLimiter.check(max: max, window_ms: window_ms, key: :refill_test)
    end

    test "different keys have independent buckets" do
      Ectomancer.RateLimiter.check(max: 1, window_ms: 60_000, key: :alice)
      # Alice is rate limited
      assert {:error, :rate_limited, _} =
               Ectomancer.RateLimiter.check(max: 1, window_ms: 60_000, key: :alice)

      # Bob still has tokens
      assert :ok = Ectomancer.RateLimiter.check(max: 1, window_ms: 60_000, key: :bob)
    end

    test "default key is :global" do
      assert :ok = Ectomancer.RateLimiter.check(max: 1, window_ms: 60_000)
      assert {:error, :rate_limited, _} = Ectomancer.RateLimiter.check(max: 1, window_ms: 60_000)
    end

    test "handles large max values" do
      results =
        Enum.map(1..10, fn _ ->
          Ectomancer.RateLimiter.check(max: 1000, window_ms: 60_000, key: :large_test)
        end)

      assert Enum.all?(results, &(&1 == :ok))
    end

    test "window_ms of 0 never refills" do
      Ectomancer.RateLimiter.check(max: 1, window_ms: 0, key: :no_refill)
      assert {:error, :rate_limited, _} =
               Ectomancer.RateLimiter.check(max: 1, window_ms: 0, key: :no_refill)
    end
  end

  describe "reset/0" do
    test "clears all buckets" do
      Ectomancer.RateLimiter.check(max: 1, window_ms: 60_000, key: :reset_test)
      assert {:error, :rate_limited, _} =
               Ectomancer.RateLimiter.check(max: 1, window_ms: 60_000, key: :reset_test)

      Ectomancer.RateLimiter.reset()
      assert :ok = Ectomancer.RateLimiter.check(max: 1, window_ms: 60_000, key: :reset_test)
    end
  end
end
