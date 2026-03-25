defmodule Ectomancer.RouteIntrospection do
  @moduledoc """
  Phoenix route introspection for Ectomancer.

  This module requires Plug to be available at runtime for route execution.
  """

  @http_method_prefixes %{
    "GET" => "get",
    "POST" => "post",
    "PUT" => "put",
    "PATCH" => "patch",
    "DELETE" => "delete",
    "*" => "call"
  }

  @doc """
  Parses a Phoenix route path and extracts parameters.
  """
  @spec parse_path_params(String.t()) :: {String.t(), [{atom(), :param | :glob}]}
  def parse_path_params(path) do
    segments = String.split(path, "/", trim: true)
    {static_parts, params} = parse_segments(segments)
    static_path = "/" <> Enum.join(static_parts, "/") <> "/"
    {static_path, params}
  end

  defp parse_segments(segments) do
    Enum.reduce(segments, {[], []}, fn segment, {static, params} ->
      cond do
        String.starts_with?(segment, ":") ->
          param_name = String.slice(segment, 1..-1//1)
          {static, [{String.to_atom(param_name), :param} | params]}

        String.starts_with?(segment, "*") ->
          param_name = String.slice(segment, 1..-1//1)
          {static, [{String.to_atom(param_name), :glob} | params]}

        String.contains?(segment, ":") ->
          [static_part, param_part] = String.split(segment, ":")
          param_name = String.to_atom(param_part)
          {[static_part | static], [{param_name, :param} | params]}

        true ->
          {[segment | static], params}
      end
    end)
    |> then(fn {s, p} -> {Enum.reverse(s), Enum.reverse(p)} end)
  end

  @doc """
  Builds a tool name from a route.
  """
  @spec build_tool_name({String.t(), String.t(), module(), atom()}) :: atom()
  def build_tool_name(route), do: build_tool_name(route, nil)

  @spec build_tool_name({String.t(), String.t(), module(), atom()}, atom() | nil) :: atom()
  def build_tool_name({method, path, _controller, _action}, namespace) do
    {has_params, path_segments} = extract_path_segments(path)

    method_prefix = Map.get(@http_method_prefixes, method)
    path_part = Enum.join(path_segments, "_")

    resource_name =
      if path_part != "" do
        if has_params do
          singularize(path_part)
        else
          path_part
        end
      else
        "root"
      end

    base_name = "#{method_prefix}_#{resource_name}"

    if namespace do
      String.to_atom("#{namespace}_#{base_name}")
    else
      String.to_atom(base_name)
    end
  end

  defp extract_path_segments(path) do
    segments = String.split(path, "/", trim: true)
    has_params = Enum.any?(segments, &has_param?/1)

    clean_segments =
      Enum.map(segments, fn segment ->
        cond do
          String.starts_with?(segment, ":") -> nil
          String.starts_with?(segment, "*") -> nil
          String.contains?(segment, ":") -> String.split(segment, ":")[0]
          true -> segment
        end
      end)
      |> Enum.reject(&is_nil/1)

    {has_params, clean_segments}
  end

  defp has_param?(segment) do
    String.starts_with?(segment, ":") or
      String.starts_with?(segment, "*") or
      String.contains?(segment, ":")
  end

  defp singularize(name) do
    if String.ends_with?(name, "s") and not String.ends_with?(name, "ss"),
      do: String.slice(name, 0..-2//1),
      else: name
  end

  @doc """
  Extracts routes from a Phoenix router module.
  """
  @spec get_routes(module()) :: [{String.t(), String.t(), module(), atom()}]
  def get_routes(router_module) do
    if function_exported?(router_module, :__routes__, 0) do
      router_module.__routes__()
      |> extract_routes()
    else
      []
    end
  end

  defp extract_routes(routes) when is_list(routes) do
    routes
    |> Enum.flat_map(fn
      %{} = route ->
        extract_from_map_route(route)

      {path, spec} when is_tuple(spec) ->
        extract_from_spec(path, spec)

      {_path, nested_routes} when is_list(nested_routes) ->
        extract_routes(nested_routes)

      _ ->
        []
    end)
  end

  defp extract_from_map_route(%{
         path: path,
         plug: controller,
         plug_opts: action,
         verb: verb
       }) do
    method =
      case verb do
        :* -> "*"
        :get -> "GET"
        :post -> "POST"
        :put -> "PUT"
        :patch -> "PATCH"
        :delete -> "DELETE"
        other -> to_string(other) |> String.upcase()
      end

    [{method, path, controller, action}]
  end

  defp extract_from_map_route(_), do: []

  defp extract_from_spec(path, {method, controller, action, _opts}) do
    [{method, path, controller, action}]
  end

  defp extract_from_spec(_path, _spec) do
    []
  end

  @doc """
  Filters routes based on options.
  """
  @spec filter_routes([{String.t(), String.t(), module(), atom()}], keyword()) ::
          [{String.t(), String.t(), module(), atom()}]
  def filter_routes(routes, opts) do
    only = Keyword.get(opts, :only)
    except = Keyword.get(opts, :except)
    methods = Keyword.get(opts, :methods)

    routes
    |> filter_by_only(only)
    |> filter_by_except(except)
    |> filter_by_methods(methods)
  end

  defp filter_by_only(routes, nil), do: routes

  defp filter_by_only(routes, only) do
    Enum.filter(routes, fn {_method, path, _controller, _action} ->
      path in only
    end)
  end

  defp filter_by_except(routes, nil), do: routes

  defp filter_by_except(routes, except) do
    Enum.reject(routes, fn {_method, path, _controller, _action} ->
      path in except
    end)
  end

  defp filter_by_methods(routes, nil), do: routes

  defp filter_by_methods(routes, methods) do
    Enum.filter(routes, fn {method, _path, _controller, _action} ->
      method in methods
    end)
  end

  @doc """
  Exposes Phoenix routes as MCP tools.
  """
  defmacro expose_routes(router_module, opts \\ []) do
    router = Macro.expand(router_module, __CALLER__)

    validate_router!(router)

    routes = get_routes(router)
    filtered_routes = filter_routes(routes, opts)

    namespace = Keyword.get(opts, :namespace)

    tool_definitions =
      Enum.map(filtered_routes, fn route ->
        tool_name = build_tool_name(route, namespace)
        check_collision!(__CALLER__.module, tool_name)
        generate_route_tool(route, tool_name, namespace)
      end)

    quote do
      (unquote_splicing(tool_definitions))
    end
  end

  defp validate_router!(router) do
    unless Code.ensure_loaded?(Plug) do
      raise ArgumentError,
            "expose_routes requires Plug to be available. " <>
              "Add {:plug, \"~> 1.16\"} to your dependencies."
    end

    case Code.ensure_compiled(router) do
      {:module, _} ->
        :ok

      {:error, reason} ->
        raise ArgumentError,
              "Could not compile router #{inspect(router)}: #{reason}. "
    end

    unless function_exported?(router, :__routes__, 0) do
      raise ArgumentError,
            "Router #{inspect(router)} does not implement __routes__/0. "
    end
  end

  defp check_collision!(caller_module, tool_name) do
    tool_module = Module.concat(caller_module, "Tool.#{Macro.camelize(to_string(tool_name))}")

    if Code.ensure_loaded?(tool_module) do
      IO.warn("Route tool naming collision: #{tool_name}")
    end
  end

  defp generate_route_tool(route, tool_name, namespace) do
    {method, path, controller, action} = route

    {_path_template, route_params} = parse_path_params(path)

    description = build_route_description(method, path, controller, action, namespace)

    handler =
      quote do
        fn params, _actor ->
          execute_route(
            unquote(method),
            unquote(path),
            unquote(controller),
            unquote(action),
            params
          )
        end
      end

    param_declarations = build_param_declarations(route_params)

    quote do
      import Ectomancer.RouteIntrospection, only: [execute_route: 5]

      tool unquote(tool_name) do
        description(unquote(description))
        unquote(param_declarations)
        authorize(:none)
        handle(unquote(handler))
      end
    end
  end

  defp build_param_declarations([]), do: quote(do: :ok)

  defp build_param_declarations(route_params) do
    route_params
    |> Enum.map(fn {param_name, _param_type} ->
      quote do
        param(unquote(param_name), :string)
      end
    end)
    |> case do
      [] -> quote(do: :ok)
      [single] -> single
      multiple -> {:__block__, [], multiple}
    end
  end

  defp build_route_description(method, path, controller, action, namespace) do
    base = "HTTP #{method} #{path} - #{Macro.underscore(controller)}##{action}"

    if namespace do
      "[#{namespace}] #{base}"
    else
      base
    end
  end

  @doc false
  def execute_route(method, path, controller, action, params) do
    validate_plug_available!()

    {url, path_params} = build_url_with_params(path, params)
    http_method = normalize_http_method(method)
    conn = build_plug_conn(http_method, url, params, path_params)
    string_params = normalize_params(params)

    try do
      controller
      |> apply(action, [conn, string_params])
      |> format_controller_result()
    catch
      :error, %Plug.Conn.AlreadySentError{} ->
        {:ok, "Response sent"}

      kind, reason ->
        {:error, "Controller error (#{kind}): #{inspect(reason)}"}
    end
  end

  defp validate_plug_available! do
    unless Code.ensure_loaded?(Plug) do
      raise ArgumentError,
            "expose_routes requires Plug to be available. Add {:plug, \"~> 1.16\"} to your dependencies."
    end
  end

  defp normalize_http_method("*"), do: "GET"
  defp normalize_http_method(method), do: method

  defp normalize_params(params) do
    for {k, v} <- params, into: %{}, do: {to_string(k), v}
  end

  defp format_controller_result(%Plug.Conn{state: :sent} = conn) do
    {:ok, "Status: #{conn.status} - Request processed successfully"}
  end

  defp format_controller_result(%Plug.Conn{} = conn) do
    {:ok, "Status: #{conn.status || 200} - Request processed"}
  end

  defp format_controller_result(result) do
    {:ok, "Status: 200 - Request processed: #{inspect(result)}"}
  end

  defp build_plug_conn(method, url, _params, path_params) do
    # Create connection with Plug.Test - this sets up a proper test adapter
    # The empty string body allows read_body to work without issues
    conn = Plug.Test.conn(method, url, "")

    # Add private fields needed by Phoenix
    conn =
      conn
      |> Plug.Conn.put_private(:phoenix_router, true)
      |> Plug.Conn.put_private(:phoenix_endpoint, true)
      |> Plug.Conn.put_private(:plug_skip_csrf_protection, true)

    # Fetch query params and set path params
    conn = Plug.Conn.fetch_query_params(conn)
    %{conn | path_params: path_params}
  end

  defp build_url_with_params(path_template, params) do
    path_params =
      path_template
      |> String.split("/", trim: true)
      |> Enum.filter(&String.starts_with?(&1, ":"))
      |> Enum.map(fn ":" <> param -> param end)

    url =
      Enum.reduce(path_params, path_template, fn param, url ->
        placeholder = ":#{param}"
        value = Map.get(params, param, Map.get(params, String.to_atom(param), placeholder))
        String.replace(url, placeholder, to_string(value))
      end)

    path_params_map =
      path_params
      |> Enum.flat_map(fn param ->
        value = Map.get(params, param, Map.get(params, String.to_atom(param), nil))

        if value do
          [{param, value}, {String.to_atom(param), value}]
        else
          []
        end
      end)
      |> Enum.into(%{})

    {url, path_params_map}
  end
end
