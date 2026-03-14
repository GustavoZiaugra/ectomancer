defmodule Ectomancer.Tool do
  @moduledoc """
  Custom tool DSL for defining MCP tools.

  ## Example

      defmodule MyApp.MCP do
        use Ectomancer

        tool :send_password_reset do
          description "Send a password reset email to a user"
          param :email, :string, required: true
          handle fn %{email: email}, actor ->
            MyApp.Accounts.send_reset_email(email, actor)
          end
        end
      end
  """

  # NOTE: Implement tool macro DSL
end
