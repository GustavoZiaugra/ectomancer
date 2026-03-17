defmodule Ectomancer.Authorization.Policy do
  @moduledoc """
  Behavior for authorization policy modules.

  Policy modules implement authorization logic that can be reused across tools.

  ## Example

      defmodule MyApp.Policies.UserPolicy do
        @behaviour Ectomancer.Authorization.Policy

        @impl true
        def authorize(actor, action, opts \\\\ []) do
          case actor.role do
            :admin -> :ok
            :user when action in [:list, :get] -> :ok
            _ -> {:error, "Unauthorized"}
          end
        end
      end

  ## Usage

      expose MyApp.Accounts.User,
        authorize: with: MyApp.Policies.UserPolicy
  """

  @doc """
  Authorizes an action.

  ## Parameters

    * `actor` - The current actor (from frame.assigns[:ectomancer_actor])
    * `action` - The action being performed (e.g., :list, :get, :create)
    * `opts` - Optional context (e.g., schema, params)

  ## Returns

    * `:ok` - Authorization passed
    * `{:error, reason}` - Authorization failed
  """
  @callback authorize(actor :: any(), action :: atom(), opts :: keyword()) ::
              :ok | {:error, String.t()}
end
