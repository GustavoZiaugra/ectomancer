defmodule Ectomancer.Scope do
  @moduledoc false

  @doc false
  def compose(policy_scope, _actor, nil), do: policy_scope

  def compose(nil, actor, config_scope) when is_function(config_scope, 2) do
    fn query -> config_scope.(query, actor) end
  end

  def compose(policy_scope, actor, config_scope) when is_function(config_scope, 2) do
    fn query -> query |> policy_scope.() |> config_scope.(actor) end
  end
end
