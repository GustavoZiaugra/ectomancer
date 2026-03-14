import Config

# Example configuration for actor extraction
# Uncomment and customize for your application:

# config :ectomancer,
#   actor_from: fn conn ->
#     conn
#     |> Plug.Conn.get_req_header("authorization")
#     |> List.first()
#     |> case do
#       nil -> {:error, :unauthorized}
#       token -> MyApp.Auth.verify_token(token)
#     end
#   end
