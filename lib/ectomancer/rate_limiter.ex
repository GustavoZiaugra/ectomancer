defmodule Ectomancer.RateLimiter do
  @moduledoc """
  Token bucket rate limiter backed by ETS.

  Provides global and per-actor rate limiting for MCP tool calls.
  Designed for LLM clients that may make rapid consecutive requests.

  ## Configuration

  Configure globally in `config.exs`:

      config :ectomancer, :rate_limit,
        max: 100,
        window_ms: 60_000,
        per_actor: false

  Or inline in `use Ectomancer`:

      use Ectomancer,
        name: "my-app",
        rate_limit: [max: 100, window_ms: 60_000]

  ## Algorithm

  Token bucket with self-refilling tokens. On each request:

    1. Read bucket state `{key, tokens, last_refilled_at}`
    2. Calculate new tokens based on elapsed time since last refill
    3. Cap at `max` (burst capacity)
    4. If >= 1 token available: consume one, write new state
    5. If no tokens: return `{:error, :rate_limited, retry_after_ms}`
  """

  @table_name :ectomancer_rate_limit

  @doc """
  Initializes the ETS table. Idempotent — safe to call multiple times.
  """
  @spec init() :: :ok
  def init do
    case :ets.info(@table_name) do
      :undefined ->
        :ets.new(@table_name, [:set, :public, :named_table, write_concurrency: true])

      _ ->
        :ok
    end

    :ok
  end

  @doc """
  Checks if a request is within configured rate limits.

  ## Options

    * `:max` — Maximum token capacity (burst limit). Default: `100`
    * `:window_ms` — Refill window in milliseconds. Default: `60_000`
    * `:key` — Bucket identifier. Default: `:global`

  ## Returns

    * `:ok` — Request allowed, one token consumed
    * `{:error, :rate_limited, retry_after_ms}` — Denied, suggests retry delay
  """
  @spec check(keyword()) :: :ok | {:error, :rate_limited, non_neg_integer()}
  def check(opts \\ []) do
    init()

    max = Keyword.get(opts, :max, 100)
    window_ms = Keyword.get(opts, :window_ms, 60_000)
    key = Keyword.get(opts, :key, :global)

    refill_rate = if window_ms > 0, do: max / (window_ms / 1000), else: 0
    now = System.monotonic_time(:millisecond)

    {tokens, refilled_at} =
      case :ets.lookup(@table_name, key) do
        [{^key, tokens, refilled_at}] -> {tokens, refilled_at}
        [] -> {max, now}
      end

    elapsed_ms = now - refilled_at
    gained = elapsed_ms * refill_rate / 1000
    new_tokens = min(max, tokens + gained)

    if new_tokens >= 1 do
      :ets.insert(@table_name, {key, new_tokens - 1, now})
      :ok
    else
      retry_after =
        if refill_rate > 0 do
          ceil((1 - new_tokens) / refill_rate * 1000)
        else
          window_ms
        end

      {:error, :rate_limited, retry_after}
    end
  end

  @doc """
  Resets all rate limit buckets. Useful for testing.
  """
  @spec reset() :: :ok
  def reset do
    case :ets.info(@table_name) do
      :undefined -> :ok
      _ -> :ets.delete_all_objects(@table_name)
    end

    :ok
  end
end
