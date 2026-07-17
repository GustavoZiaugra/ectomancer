# credo:disable-for-this-file Credo.Check.Refactor.FunctionArity
defmodule Ectomancer.Resource do
  @moduledoc """
  Custom resource DSL for defining MCP resources.

  Resources are one of the three MCP primitives (tools, resources, prompts).
  They represent **data** that the LLM can **read** - documents, metrics, logs,
  configuration, or any content identified by a URI.

  ## Examples

      defmodule MyApp.MCP do
        use Ectomancer

        # Static resource — fixed URI
        resource :system_status do
          description "Current system health metrics"
          uri "metrics://status"
          mime_type "application/json"

          read fn _params, _actor ->
            status = %{status: "healthy", uptime: System.uptime(), memory: :erlang.memory()}
            {:ok, Jason.encode!(status)}
          end
        end

        # Templated resource — URI with parameters
        resource :documentation do
          description "Project documentation files"
          uri "docs://{path}"
          mime_type "text/markdown"

          read fn %{path: path}, _actor ->
            case File.read("docs/\#{path}.md") do
              {:ok, content} -> {:ok, content}
              _ -> {:error, :not_found}
            end
          end
        end

        # Resource with authorization
        resource :admin_metrics do
          description "Admin-only system metrics"
          uri "admin://metrics"
          mime_type "application/json"

          authorize fn actor, _action ->
            actor != nil && actor.role == :admin
          end

          read fn _params, _actor ->
            {:ok, Jason.encode!(MyApp.System.sensitive_metrics())}
          end
        end
      end

  ## DSL Functions

  - `description/1` - Human-readable description of the resource
  - `uri/1` - Resource URI (static: `"docs://readme"` or templated: `"docs://{path}"`)
  - `mime_type/1` - MIME type of the content (default: `"text/plain"`)
  - `authorize/1` - Optional authorization handler
  - `read/1` - Handler function `fn params, actor -> {:ok, content} | {:error, reason} end`

  ## URI Templates

  URI templates follow RFC 6570 Level 1 syntax: `{variable}` placeholders in the
  URI path. When the LLM reads a resource by a concrete URI that matches the
  template pattern, the extracted variables are passed as a map to the read handler.

  ## Return Values

  The read handler should return:

  - `{:ok, content}` - Content is a string (will be served with the configured mime_type)
  - `{:error, reason}` - Reason can be `:not_found` (will return proper MCP error) or
    a custom string (returned as generic error)
  """

  alias Ectomancer.Authorization

  @doc """
  Defines a new resource within an Ectomancer module.

  ## Example

      resource :system_status do
        description "Current system metrics"
        uri "metrics://status"
        mime_type "application/json"

        read fn _params, _actor ->
          {:ok, Jason.encode!(%{status: "healthy"})}
        end
      end
  """
  defmacro resource(name, do: block) do
    resource_name_str = to_string(name)

    {description, uri_str, mime_type_str, auth_handler, read_handler_ast} =
      parse_resource_block(block)

    # Determine if URI is static or templated (contains {var} patterns)
    is_template = String.contains?(uri_str, "{")
    action = :read

    quote do
      resource_module_name =
        Module.concat(__MODULE__, "Resource.#{Macro.camelize(unquote(resource_name_str))}")

      Ectomancer.Resource.define_resource_module(
        resource_module_name,
        unquote(resource_name_str),
        unquote(description),
        unquote(uri_str),
        unquote(mime_type_str),
        unquote(is_template),
        unquote(auth_handler),
        unquote(action),
        unquote(read_handler_ast)
      )

      require Anubis.Server
      Anubis.Server.component(resource_module_name, name: unquote(resource_name_str))
    end
  end

  @doc false
  # credo:disable-for-next-line Credo.Check.Refactor.CyclomaticComplexity
  defmacro define_resource_module(
             module_name,
             resource_name,
             description,
             uri_str,
             mime_type_str,
             is_template,
             auth_handler,
             action,
             read_handler_ast
           ) do
    quote do
      defmodule unquote(module_name) do
        @moduledoc unquote(description)
        @resource_name unquote(resource_name)
        @action unquote(action)

        def name, do: @resource_name
        def description, do: @moduledoc
        def __mcp_component_type__, do: :resource
        def __description__, do: @moduledoc

        if unquote(is_template) do
          def uri_template, do: unquote(uri_str)
        else
          def uri, do: unquote(uri_str)
        end

        def mime_type, do: unquote(mime_type_str)

        unquote(
          if auth_handler do
            quote do
              def read(params, frame) do
                actor = frame.assigns[:ectomancer_actor]

                case check_authorization(actor, @action) do
                  :ok ->
                    handler = unquote(read_handler_ast)
                    do_read(handler, params, actor, frame)

                  {:error, reason} ->
                    error = %Anubis.MCP.Error{
                      code: -32_001,
                      message: "Unauthorized: #{reason}",
                      data: %{}
                    }

                    {:error, error, frame}
                end
              end

              defp check_authorization(actor, action) do
                case Ectomancer.Authorization.check(actor, action, handler: unquote(auth_handler)) do
                  {:ok, _result} -> :ok
                  {:error, reason} -> {:error, reason}
                  :ok -> :ok
                end
              end
            end
          else
            quote do
              def read(params, frame) do
                actor = frame.assigns[:ectomancer_actor]
                handler = unquote(read_handler_ast)
                do_read(handler, params, actor, frame)
              end
            end
          end
        )

        @dialyzer {:nowarn_function, do_read: 4}
        defp do_read(handler, params, actor, frame) when is_function(handler, 2) do
          # For templated resources, Anubis wraps extracted URI variables in "params" key.
          # For static resources, params contains just {"uri" => uri} which the handler ignores.
          handler_params =
            if unquote(is_template) do
              Map.get(params, "params", %{})
            else
              params
            end

          result = handler.(handler_params, actor)

          case result do
            {:ok, content} when is_binary(content) ->
              response = %Anubis.Server.Response{
                type: :resource,
                content: [%{"type" => "text", "text" => content}]
              }

              {:reply, response, frame}

            {:error, :not_found} ->
              error = %Anubis.MCP.Error{
                code: -32_002,
                message: "Resource not found",
                data: %{}
              }

              {:error, error, frame}

            {:error, reason} when is_binary(reason) ->
              error = %Anubis.MCP.Error{
                code: -32_603,
                message: "Resource read failed: #{reason}",
                data: %{}
              }

              {:error, error, frame}

            {:error, _reason} ->
              error = %Anubis.MCP.Error{
                code: -32_603,
                message: "Resource read failed",
                data: %{}
              }

              {:error, error, frame}
          end
        rescue
          e ->
            error = %Anubis.MCP.Error{
              code: -32_603,
              message: "Resource read error: #{Exception.message(e)}",
              data: %{error: inspect(e), stacktrace: Exception.format_stacktrace(__STACKTRACE__)}
            }

            {:error, error, frame}
        end
      end
    end
  end

  # Parse resource block to extract components
  defp parse_resource_block(block) do
    # Handle the block which may contain nested __block__ structures
    items =
      case block do
        {:__block__, _, inner_items} -> flatten_block_items(inner_items)
        single -> [single]
      end

    Enum.reduce(
      items,
      {"", "resource://default", "text/plain", nil,
       quote(do: fn _params, _actor -> {:ok, ""} end)},
      fn item, {desc, uri, mime, auth_handler, handler} ->
        case item do
          {:description, _, [text]} ->
            {text, uri, mime, auth_handler, handler}

          {:uri, _, [text]} ->
            {desc, text, mime, auth_handler, handler}

          {:mime_type, _, [text]} ->
            {desc, uri, text, auth_handler, handler}

          {:authorize, _, [handler_ast]} ->
            auth = Authorization.parse_handler(handler_ast)
            {desc, uri, mime, auth, handler}

          {:read, _, [handler_block]} ->
            {desc, uri, mime, auth_handler, handler_block}

          _ ->
            {desc, uri, mime, auth_handler, handler}
        end
      end
    )
  end

  # Flatten nested __block__ items
  @doc false
  def flatten_block_items(items) do
    Enum.flat_map(items, fn
      {:__block__, _, inner} -> flatten_block_items(inner)
      other -> [other]
    end)
  end

  @doc false
  defdelegate parse_authorize_handler(handler), to: Ectomancer.Authorization, as: :parse_handler
end
