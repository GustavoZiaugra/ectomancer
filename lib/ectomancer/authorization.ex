defmodule Ectomancer.Authorization do
  @moduledoc """
  Authorization system for Ectomancer tools.

  Supports three authorization strategies:

  1. **Inline function** - Simple authorization with a function
     ```elixir
     authorize fn actor, action ->
       actor.role == :admin or action in [:list, :get]
     end
     ```

  2. **Policy module** - Complex authorization with a policy module
     ```elixir
     authorize with: MyApp.Policies.UserPolicy
     ```

  3. **No authorization** - Public access
     ```elixir
     authorize :none
     ```

  ## Cascade Authorization

  Authorization can be defined at three levels (from broadest to specific):

  1. **Global** (in `use Ectomancer`)
  2. **Schema** (in `expose/2`)
  3. **Action** (in `expose/2` with action-specific rules)

  When multiple levels are defined, they cascade:
  - All levels must pass for authorization to succeed
  - If any level fails, the tool returns an unauthorized error
  """

  @doc """
  Checks authorization for a tool execution.

  ## Parameters

    * `actor` - The current actor (from frame.assigns[:ectomancer_actor])
    * `action` - The action being performed (e.g., :list, :get, :create)
    * `opts` - Authorization options
      * `:handler` - The authorization handler (function, module, or :none)
      * `:schema` - The schema module (for context)
      * `:parent_auth` - Parent authorization config for cascading

  ## Returns

    * `:ok` - Authorization passed
    * `{:error, reason}` - Authorization failed with reason
  """
  @spec check(any(), atom(), keyword()) :: :ok | {:error, String.t()}
  def check(actor, action, opts) do
    handler = Keyword.get(opts, :handler)
    parent_auth = Keyword.get(opts, :parent_auth)

    # First check parent authorization (cascade)
    with :ok <- check_parent(parent_auth, actor, action),
         :ok <- do_check(handler, actor, action) do
      :ok
    end
  end

  @doc """
  Checks if authorization is configured.
  """
  @spec enabled?(keyword()) :: boolean()
  def enabled?(opts) do
    handler = Keyword.get(opts, :handler)
    parent_auth = Keyword.get(opts, :parent_auth)

    handler not in [nil, :none] or
      (is_list(parent_auth) and enabled?(parent_auth))
  end

  # Private functions

  defp check_parent(nil, _actor, _action), do: :ok
  defp check_parent([], _actor, _action), do: :ok

  defp check_parent(parent_auth, actor, action) when is_list(parent_auth) do
    handler = Keyword.get(parent_auth, :handler)
    do_check(handler, actor, action)
  end

  defp do_check(nil, _actor, _action), do: :ok
  defp do_check(:none, _actor, _action), do: :ok

  defp do_check(handler, actor, action) when is_function(handler, 2) do
    case handler.(actor, action) do
      true -> :ok
      false -> {:error, "Unauthorized access to #{action}"}
      {:ok, true} -> :ok
      {:ok, false} -> {:error, "Unauthorized access to #{action}"}
      {:error, reason} -> {:error, reason}
      _ -> {:error, "Authorization check failed"}
    end
  end

  defp do_check(module, actor, action) when is_atom(module) do
    if Code.ensure_loaded?(module) do
      call_policy_module(module, actor, action)
    else
      {:error, "Policy module #{inspect(module)} not found"}
    end
  end

  defp do_check({module, opts}, actor, action) when is_atom(module) do
    if Code.ensure_loaded?(module) do
      call_policy_module(module, actor, action, opts)
    else
      {:error, "Policy module #{inspect(module)} not found"}
    end
  end

  defp do_check(handler, _actor, action) do
    {:error, "Invalid authorization handler for #{action}: #{inspect(handler)}"}
  end

  defp call_policy_module(module, actor, action, opts \\ []) do
    # Check if module implements the behavior
    cond do
      function_exported?(module, :authorize, 3) ->
        module.authorize(actor, action, opts)

      function_exported?(module, :authorize, 2) ->
        module.authorize(actor, action)

      true ->
        {:error, "Policy module #{inspect(module)} does not implement authorize/2 or authorize/3"}
    end
  end
end
