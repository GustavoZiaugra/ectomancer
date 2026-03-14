defmodule Ectomancer do
  @moduledoc """
  Ectomancer - Add an AI brain to your Phoenix app.

  Automatically exposes your Ecto schemas as MCP (Model Context Protocol) tools,
  making your Phoenix app conversationally operable by Claude and other LLMs.

  ## Quick Start

      # In your router
      forward "/mcp", Ectomancer.Plug

      # In a dedicated module
      defmodule MyApp.MCP do
        use Ectomancer

        tool :send_password_reset do
          description "Send a password reset email"
          param :email, :string, required: true
          handle fn %{email: email}, actor ->
            MyApp.Accounts.send_reset_email(email, actor)
          end
        end
      end

  ## Configuration

      # config/config.exs
      config :ectomancer,
        actor_from: fn conn ->
          conn
          |> get_req_header("authorization")
          |> MyApp.Auth.resolve_user()
        end
  """

  @doc """
  Returns the version of Ectomancer.
  """
  def version do
    "0.1.0"
  end
end
