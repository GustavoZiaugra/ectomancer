defmodule Ectomancer.Telemetry do
  @moduledoc false

  @tool_event [:ectomancer, :tool]
  @repo_event [:ectomancer, :repo]
  @auth_denied_event [:ectomancer, :authorization, :denied]
  @rate_limited_event [:ectomancer, :rate_limit, :exceeded]

  @doc false
  def enabled?, do: Application.get_env(:ectomancer, :telemetry, true)

  @doc false
  def tool_span(tool_name, fun) do
    if enabled?() do
      :telemetry.span(@tool_event, %{tool: tool_name}, fn ->
        result = fun.()
        {result, %{tool: tool_name}}
      end)
    else
      fun.()
    end
  end

  @doc false
  def repo_span(action, schema, fun) do
    if enabled?() do
      :telemetry.span(@repo_event, %{action: action, schema: schema}, fn ->
        result = fun.()
        {result, %{action: action, schema: schema}}
      end)
    else
      fun.()
    end
  end

  @doc false
  def auth_denied(actor, action, handler) do
    if enabled?() do
      :telemetry.execute(@auth_denied_event, %{}, %{
        actor: actor,
        action: action,
        handler: inspect(handler)
      })
    end

    :ok
  end

  @doc false
  def rate_limited(key, window_ms) do
    if enabled?() do
      :telemetry.execute(@rate_limited_event, %{}, %{
        key: inspect(key),
        window_ms: window_ms
      })
    end

    :ok
  end
end
