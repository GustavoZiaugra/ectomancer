if Code.ensure_loaded?(Phoenix.Socket.Transport) do
  defmodule Ectomancer.Plug.WebSocket do
    @moduledoc """
    WebSocket transport for Ectomancer via `Phoenix.Socket.Transport`.

    Provides bidirectional JSON-RPC communication over WebSocket, with
    Anubis session management for tool execution and actor propagation.

    ## Phoenix Router Integration

    In your endpoint:

        socket "/mcp/ws", Ectomancer.Plug.WebSocket,
          server: MyApp.MCP,
          websocket: [connect_info: [:x_headers, :uri, :peer_data, :user_agent]]

    The `connect_info` option controls what HTTP request metadata is available
    during the WebSocket handshake for actor extraction.

    ## Actor Extraction

    Actor extraction for WebSocket differs from HTTP — there is no `Plug.Conn`.
    The configured `actor_from` function receives a map with the following keys
    when invoked from a WebSocket connection:

      - `:params` — query params from the WebSocket URL
      - `:connect_info` — configured connection info (`:x_headers`, `:uri`, etc.)

    Example actor_from that handles both HTTP and WebSocket:

        config :ectomancer,
          actor_from: fn
            %Plug.Conn{} = conn ->
              Ectomancer.Plug.extract_bearer_token(conn) |> verify_token()

            ws_info when is_map(ws_info) ->
              # WebSocket: extract token from query param or x-headers
              case ws_info.params["token"] do
                nil ->
                  # Try Authorization header from x_headers
                  headers = (ws_info.connect_info[:x_headers] || [])
                  {_, token} = List.keyfind(headers, "authorization", 0, {nil, nil})
                  String.replace_prefix(token || "", "Bearer ", "") |> verify_token()
                token -> verify_token(token)
              end
          end

    If no `actor_from` is configured, the actor defaults to `nil`.

    ## Auth via `connect` return value

    Return `{:error, reason}` from the Phoenix socket connect callback to reject
    the WebSocket connection before any MCP messages are processed.
    """

    @behaviour Phoenix.Socket.Transport

    require Logger

    alias Anubis.MCP.ID
    alias Anubis.MCP.Message
    alias Anubis.Server.Supervisor, as: ServerSupervisor

    @doc false
    @impl Phoenix.Socket.Transport
    def child_spec(_opts), do: :ignore

    @doc false
    @impl Phoenix.Socket.Transport
    def drainer_spec(_opts), do: :ignore

    @impl Phoenix.Socket.Transport
    def connect(state) do
      server = resolve_server(state)

      if is_nil(server) do
        Logger.error(
          "Ectomancer.Plug.WebSocket requires a server module. " <>
            "Configure it via config :ectomancer, :ws_server, MyApp.MCP"
        )

        {:error, :missing_server_option}
      else
        actor = extract_actor(state)

        {:ok,
         %{
           server: server,
           actor: actor,
           session_pid: nil,
           timeout: 30_000,
           params: Map.get(state, :params) || %{},
           connect_info: Map.get(state, :connect_info) || %{}
         }}
      end
    end

    @impl Phoenix.Socket.Transport
    def init(state) do
      session_id = ID.generate_session_id()
      session_config = ServerSupervisor.get_session_config(state.server)

      session_opts = [
        session_id: session_id,
        server_module: state.server,
        name: Module.concat(state.server, :"WS_#{session_id}"),
        transport: session_config.transport,
        session_idle_timeout: session_config.session_idle_timeout || 1_800_000,
        timeout: session_config.timeout || 30_000,
        task_supervisor: session_config.task_supervisor,
        task_store: Map.get(session_config, :task_store)
      ]

      case Anubis.Server.Supervisor.start_session(state.server, session_opts) do
        {:ok, pid} ->
          timeout = session_config.timeout || 30_000
          {:ok, %{state | session_pid: pid, timeout: timeout}}

        {:error, {:already_started, pid}} ->
          timeout = session_config.timeout || 30_000
          {:ok, %{state | session_pid: pid, timeout: timeout}}

        {:error, reason} ->
          Logger.error("Ectomancer.WebSocket: failed to start session: #{inspect(reason)}")
          {:stop, reason, state}
      end
    end

    @impl Phoenix.Socket.Transport
    def handle_in({message, opts}, state) when is_binary(message) and is_list(opts) do
      case Message.decode(message) do
        {:ok, [decoded]} ->
          dispatch_to_session(decoded, state)

        {:ok, messages} when is_list(messages) ->
          dispatch_messages_to_session(messages, state)

        {:error, _reason} ->
          {:reply, :ok, {:text, ~s({"error":"Invalid JSON","jsonrpc":"2.0","id":null})}, state}
      end
    end

    defp dispatch_to_session(decoded, state) do
      context = build_context(state)

      case GenServer.call(state.session_pid, {:mcp_request, decoded, context}, state.timeout) do
        {:ok, response} when is_binary(response) ->
          {:reply, :ok, {:text, response}, state}

        {:ok, nil} ->
          {:reply, :ok, {:text, "{}"}, state}

        {:error, error} ->
          {:reply, :ok, {:text, encode_error(error)}, state}
      end
    end

    defp dispatch_messages_to_session(messages, state) do
      context = build_context(state)

      Enum.reduce_while(messages, {:ok, state}, fn msg, {:ok, _acc_state} ->
        case GenServer.call(state.session_pid, {:mcp_request, msg, context}, state.timeout) do
          {:ok, response} when is_binary(response) ->
            {:halt, {:reply, :ok, {:text, response}, state}}

          {:ok, nil} ->
            {:cont, {:ok, state}}

          {:error, error} ->
            {:halt, {:reply, :ok, {:text, encode_error(error)}, state}}
        end
      end)
    end

    @impl Phoenix.Socket.Transport
    def handle_info({:mcp_notification, message}, state) do
      {:push, {:text, message}, state}
    end

    def handle_info(_message, state) do
      {:ok, state}
    end

    @impl Phoenix.Socket.Transport
    def terminate(_reason, _state), do: :ok

    ## Private helpers

    defp resolve_server(_state) do
      Application.get_env(:ectomancer, :ws_server)
    end

    defp extract_actor(state) do
      case Application.get_env(:ectomancer, :actor_from) do
        nil ->
          nil

        fun when is_function(fun, 1) ->
          info = %{
            params: Map.get(state, :params) || %{},
            connect_info: Map.get(state, :connect_info) || %{},
            transport: :websocket
          }

          fun.(info)

        _ ->
          nil
      end
    end

    defp build_context(state) do
      %{
        assigns: %{ectomancer_actor: state.actor},
        type: :websocket,
        req_headers: [],
        query_params: state.params || %{},
        auth: nil
      }
    end

    defp encode_error(%{__struct__: _} = error) do
      error |> Map.drop([:__struct__]) |> Jason.encode!()
    end

    defp encode_error(map) when is_map(map), do: Jason.encode!(map)
    defp encode_error(binary) when is_binary(binary), do: binary
  end
end
