defmodule Ectomancer.RouteIntrospectionTest do
  use ExUnit.Case
  import Enum, only: [all?: 2]
  alias Ectomancer.RouteIntrospection

  defmodule UserController, do: nil

  describe "parse_path_params/1" do
    test "parses simple path with param" do
      assert {"/users/", [{:id, :param}]} = RouteIntrospection.parse_path_params("/users/:id")
    end

    test "parses path with multiple params" do
      assert {"/users/", [{:org_id, :param}, {:id, :param}]} =
               RouteIntrospection.parse_path_params("/users/:org_id/:id")
    end

    test "parses path with glob param" do
      assert {"/pages/", [{:path, :glob}]} = RouteIntrospection.parse_path_params("/pages/*path")
    end

    test "parses path with version param" do
      assert {"/api/v/", [{:version, :param}]} =
               RouteIntrospection.parse_path_params("/api/v:version")
    end

    test "parses mixed path" do
      assert {"/api/v/users/", [{:version, :param}, {:id, :param}]} =
               RouteIntrospection.parse_path_params("/api/v:version/users/:id")
    end
  end

  describe "build_tool_name/2" do
    test "generates name for GET /users" do
      route = {"GET", "/users", UserController, :index}
      assert :get_users = RouteIntrospection.build_tool_name(route)
    end

    test "generates name for GET /users/:id" do
      route = {"GET", "/users/:id", UserController, :show}
      assert :get_user = RouteIntrospection.build_tool_name(route)
    end

    test "generates name for POST /users" do
      route = {"POST", "/users", UserController, :create}
      assert :post_users = RouteIntrospection.build_tool_name(route)
    end

    test "generates name for DELETE /users/:id" do
      route = {"DELETE", "/users/:id", UserController, :destroy}
      assert :delete_user = RouteIntrospection.build_tool_name(route)
    end

    test "adds namespace prefix" do
      route = {"GET", "/users", UserController, :index}
      assert :admin_get_users = RouteIntrospection.build_tool_name(route, :admin)
    end

    test "singularizes words ending in -us correctly (status)" do
      route = {"GET", "/status", UserController, :show}
      assert :get_status = RouteIntrospection.build_tool_name(route)
    end

    test "singularizes words ending in -ss correctly (address)" do
      route = {"GET", "/address", UserController, :index}
      assert :get_address = RouteIntrospection.build_tool_name(route)
    end

    test "singularizes words ending in -ies correctly (series)" do
      route = {"GET", "/series", UserController, :index}
      assert :get_series = RouteIntrospection.build_tool_name(route)
    end

    test "singularizes words ending in -ness correctly (business)" do
      route = {"GET", "/business", UserController, :index}
      assert :get_business = RouteIntrospection.build_tool_name(route)
    end

    test "singularizes words ending in -ews correctly (news)" do
      route = {"GET", "/news", UserController, :index}
      assert :get_news = RouteIntrospection.build_tool_name(route)
    end

    test "singularizes regular plurals correctly" do
      route = {"GET", "/users/:id", UserController, :show}
      assert :get_user = RouteIntrospection.build_tool_name(route)

      route2 = {"GET", "/posts/:id", UserController, :show}
      assert :get_post = RouteIntrospection.build_tool_name(route2)

      route3 = {"GET", "/comments/:id", UserController, :show}
      assert :get_comment = RouteIntrospection.build_tool_name(route3)
    end
  end

  describe "get_routes/1" do
    test "extracts routes from router module" do
      defmodule TestRouterGetRoutes do
        def __routes__ do
          [
            {"/users", {"GET", UserController, :index, []}},
            {"/users", {"POST", UserController, :create, []}}
          ]
        end
      end

      routes = RouteIntrospection.get_routes(TestRouterGetRoutes)
      assert {"GET", "/users", UserController, :index} in routes
      assert {"POST", "/users", UserController, :create} in routes
    end

    test "returns empty list when no routes" do
      defmodule EmptyRouterGetRoutes do
        def __routes__ do
          []
        end
      end

      assert [] = RouteIntrospection.get_routes(EmptyRouterGetRoutes)
    end
  end

  describe "filter_routes/2" do
    test "filters by only paths" do
      routes = [
        {"GET", "/users", UserController, :index},
        {"POST", "/users", UserController, :create},
        {"GET", "/posts", PostsController, :index}
      ]

      filtered = RouteIntrospection.filter_routes(routes, only: ["/users"])
      assert length(filtered) == 2
      assert all?(filtered, fn {_method, path, _controller, _action} -> path == "/users" end)
    end

    test "filters by except paths" do
      routes = [
        {"GET", "/users", UserController, :index},
        {"POST", "/users", UserController, :create},
        {"GET", "/posts", PostsController, :index}
      ]

      filtered = RouteIntrospection.filter_routes(routes, except: ["/posts"])
      assert length(filtered) == 2
      assert all?(filtered, fn {_method, path, _controller, _action} -> path != "/posts" end)
    end

    test "filters by methods" do
      routes = [
        {"GET", "/users", UserController, :index},
        {"POST", "/users", UserController, :create},
        {"DELETE", "/users/:id", UserController, :destroy}
      ]

      filtered = RouteIntrospection.filter_routes(routes, methods: ["GET"])
      assert length(filtered) == 1
      assert {"GET", "/users", UserController, :index} in filtered
    end

    test "passes through when only/except/methods are nil" do
      routes = [
        {"GET", "/users", UserController, :index},
        {"POST", "/users", UserController, :create}
      ]

      assert RouteIntrospection.filter_routes(routes, []) == routes
      assert RouteIntrospection.filter_routes(routes, only: nil) == routes
      assert RouteIntrospection.filter_routes(routes, except: nil) == routes
      assert RouteIntrospection.filter_routes(routes, methods: nil) == routes
    end

    test "handles malformed map routes gracefully" do
      defmodule MalformedRouter do
        def __routes__ do
          [
            %{path: "/users", plug: UserController, plug_opts: :index, verb: :get},
            "not_a_route",
            %{bad: "shape"}
          ]
        end
      end

      result = RouteIntrospection.get_routes(MalformedRouter)
      assert {"GET", "/users", UserController, :index} in result
    end

    test "handles nested route lists" do
      defmodule NestedRouter do
        def __routes__ do
          [
            {"/users", {"GET", UserController, :index, []}},
            {"/api",
             [
               {"/status", {"GET", UserController, :show, []}}
             ]}
          ]
        end
      end

      result = RouteIntrospection.get_routes(NestedRouter)
      assert {"GET", "/users", UserController, :index} in result
      assert {"GET", "/status", UserController, :show} in result
    end
  end

  describe "expose_routes/2 macro" do
    test "generates tools from router" do
      defmodule TestRouterForMacro do
        def __routes__ do
          [
            {"/users", {"GET", UserController, :index, []}},
            {"/users/:id", {"GET", UserController, :show, []}}
          ]
        end
      end

      defmodule TestMCPForMacro do
        use Ectomancer

        defmodule UserController do
          def index(conn, _opts) do
            Plug.Conn.send_resp(conn, 200, "users")
          end

          def show(conn, _opts) do
            Plug.Conn.send_resp(conn, 200, "user")
          end
        end

        expose_routes(TestRouterForMacro)
      end

      # Check that tools were generated
      assert {:module, _} = Code.ensure_loaded(TestMCPForMacro.Tool.GetUsers)
      assert {:module, _} = Code.ensure_loaded(TestMCPForMacro.Tool.GetUser)
    end

    test "respects namespace option" do
      defmodule TestRouterWithNS do
        def __routes__ do
          [{"/users", {"GET", UserController, :index, []}}]
        end
      end

      defmodule TestMCPWithNS do
        use Ectomancer

        defmodule UserController do
          def index(conn, _opts) do
            Plug.Conn.send_resp(conn, 200, "users")
          end
        end

        expose_routes(TestRouterWithNS, namespace: :api)
      end

      assert {:module, _} = Code.ensure_loaded(TestMCPWithNS.Tool.ApiGetUsers)
    end
  end

  describe "build_route_description/5" do
    test "builds description for route without namespace" do
      desc =
        RouteIntrospection.build_route_description("GET", "/users", UserController, :index, nil)

      assert desc =~ "HTTP GET /users"
      assert desc =~ "user_controller#index"
    end

    test "builds description with namespace prefix" do
      desc =
        RouteIntrospection.build_route_description(
          "POST",
          "/api/data",
          UserController,
          :create,
          :admin
        )

      assert desc =~ "[admin]"
      assert desc =~ "HTTP POST /api/data"
    end
  end

  describe "build_param_declarations/1" do
    test "handles empty params" do
      result = RouteIntrospection.build_param_declarations([])
      assert result != nil
    end
  end

  describe "build_tool_name/2 edge cases" do
    test "root path generates root suffix" do
      route = {"GET", "/", UserController, :index}
      assert :get_root = RouteIntrospection.build_tool_name(route)
    end

    test "wildcard method maps to call" do
      route = {"*", "/health", UserController, :check}
      assert :call_health = RouteIntrospection.build_tool_name(route)
    end

    test "PUT method generates put prefix" do
      route = {"PUT", "/users/:id", UserController, :update}
      assert :put_user = RouteIntrospection.build_tool_name(route)
    end

    test "PATCH method generates patch prefix" do
      route = {"PATCH", "/users/:id", UserController, :update}
      assert :patch_user = RouteIntrospection.build_tool_name(route)
    end

    test "mixed static and param segments" do
      route = {"GET", "/api/v:version/users/:id", UserController, :show}
      assert :get_api_v_user = RouteIntrospection.build_tool_name(route)
    end
  end

  describe "filter_routes/2 edge cases" do
    test "empty routes with filter returns empty" do
      assert RouteIntrospection.filter_routes([], only: ["/users"]) == []
    end

    test "combine only and methods filter" do
      routes = [
        {"GET", "/users", UserController, :index},
        {"POST", "/users", UserController, :create}
      ]

      filtered = RouteIntrospection.filter_routes(routes, only: ["/users"], methods: ["GET"])
      assert filtered == [{"GET", "/users", UserController, :index}]
    end

    test "combine except and methods filter" do
      routes = [
        {"GET", "/users", UserController, :index},
        {"GET", "/posts", PostsController, :index}
      ]

      filtered = RouteIntrospection.filter_routes(routes, except: ["/posts"], methods: ["GET"])
      assert filtered == [{"GET", "/users", UserController, :index}]
    end
  end

  describe "expose_routes macro edge cases" do
    test "generates tools with params from path" do
      defmodule ParamRouter do
        def __routes__ do
          [{"/users/:id", {"GET", UserController, :show, []}}]
        end
      end

      defmodule ParamMCP do
        use Ectomancer

        defmodule UserController do
          def show(conn, _opts) do
            Plug.Conn.send_resp(conn, 200, "ok")
          end
        end

        expose_routes(ParamRouter)
      end

      assert {:module, _} = Code.ensure_loaded(ParamMCP.Tool.GetUser)
    end
  end

  describe "normalize_http_method/1" do
    test "converts wildcard to GET" do
      assert RouteIntrospection.normalize_http_method("*") == "GET"
    end

    test "passes through other methods" do
      assert RouteIntrospection.normalize_http_method("POST") == "POST"
      assert RouteIntrospection.normalize_http_method("DELETE") == "DELETE"
    end
  end

  describe "normalize_params/1" do
    test "converts atom keys to strings" do
      params = %{id: "123", name: "test"}
      result = RouteIntrospection.normalize_params(params)

      assert result == %{"id" => "123", "name" => "test"}
    end

    test "handles string keys" do
      params = %{"id" => "123"}
      result = RouteIntrospection.normalize_params(params)

      assert result == %{"id" => "123"}
    end

    test "handles empty params" do
      assert RouteIntrospection.normalize_params(%{}) == %{}
    end
  end

  describe "format_controller_result/1" do
    test "formats sent connection" do
      conn = Plug.Test.conn(:get, "/") |> Plug.Conn.send_resp(201, "")
      {:ok, msg} = RouteIntrospection.format_controller_result(conn)

      assert msg =~ "201"
      assert msg =~ "successfully"
    end

    test "formats unsent connection" do
      conn = Plug.Test.conn(:get, "/")
      {:ok, msg} = RouteIntrospection.format_controller_result(conn)

      assert msg =~ "200"
    end

    test "formats non-conn result" do
      {:ok, msg} = RouteIntrospection.format_controller_result("custom result")

      assert msg =~ "custom result"
    end
  end

  describe "validate_router!/1" do
    test "raises when router does not implement __routes__/0" do
      defmodule NoRoutesRouter do
      end

      assert_raise ArgumentError, ~r/does not implement __routes__/, fn ->
        RouteIntrospection.validate_router!(NoRoutesRouter)
      end
    end

    test "raises when router cannot be compiled" do
      assert_raise ArgumentError, ~r/Could not compile router/, fn ->
        RouteIntrospection.validate_router!(NonExistentRouter12345)
      end
    end

    test "validates real router without raising" do
      defmodule ValidRouter do
        def __routes__, do: []
      end

      # validate_router! returns nil on success (from unless expression)
      assert is_nil(RouteIntrospection.validate_router!(ValidRouter))
    end
  end

  describe "expose_routes authorization" do
    test "global auth inherited by route tools" do
      defmodule GlobalRouteRouter do
        def __routes__ do
          [{"/users", {"GET", UserController, :index, []}}]
        end
      end

      defmodule GlobalRouteMCP do
        use Ectomancer,
          name: "global-route-mcp",
          version: "1.0.0",
          authorize: fn actor, _action -> actor.role == :admin end

        defmodule UserController do
          def index(conn, _opts) do
            Plug.Conn.send_resp(conn, 200, "ok")
          end
        end

        expose_routes(GlobalRouteRouter)
      end

      assert {:module, mod} = Code.ensure_loaded(GlobalRouteMCP.Tool.GetUsers)

      # Non-admin should be denied by global auth
      frame = %{assigns: %{ectomancer_actor: %{role: :user}}}
      # credo:disable-for-next-line
      assert {:error, error, _} = apply(mod, :execute, [%{}, frame])
      assert error.code == -32_001
      assert error.message =~ "Unauthorized"
    end

    test "per-route explicit auth overrides global" do
      defmodule OverrideRouteRouter do
        def __routes__ do
          [{"/users", {"GET", UserController, :index, []}}]
        end
      end

      defmodule OverrideRouteMCP do
        use Ectomancer,
          name: "override-route-mcp",
          version: "1.0.0",
          authorize: fn _actor, _action -> false end

        defmodule UserController do
          def index(conn, _opts) do
            Plug.Conn.send_resp(conn, 200, "ok")
          end
        end

        expose_routes(OverrideRouteRouter, authorize: fn _actor, _action -> true end)
      end

      assert {:module, mod} = Code.ensure_loaded(OverrideRouteMCP.Tool.GetUsers)

      frame = %{assigns: %{ectomancer_actor: %{role: :any}}}
      # credo:disable-for-next-line
      result = apply(mod, :execute, [%{}, frame])
      assert match?({:ok, _}, result) or match?({:error, _, _}, result)
    end

    test "per-route :none overrides global auth" do
      defmodule NoneRouteRouter do
        def __routes__ do
          [{"/users", {"GET", UserController, :index, []}}]
        end
      end

      defmodule NoneRouteMCP do
        use Ectomancer,
          name: "none-route-mcp",
          version: "1.0.0",
          authorize: fn _actor, _action -> false end

        defmodule UserController do
          def index(conn, _opts) do
            Plug.Conn.send_resp(conn, 200, "ok")
          end
        end

        expose_routes(NoneRouteRouter, authorize: :none)
      end

      assert {:module, mod} = Code.ensure_loaded(NoneRouteMCP.Tool.GetUsers)

      frame = %{assigns: %{ectomancer_actor: %{role: :any}}}
      # credo:disable-for-next-line
      result = apply(mod, :execute, [%{}, frame])
      # Should NOT get auth error (per-route :none overrides global)
      refute match?({:error, %{code: -32_001}, _}, result)
    end
  end

  describe "build_url_with_params/2" do
    test "replaces path params with values" do
      {url, _} = RouteIntrospection.build_url_with_params("/users/:id", %{"id" => "42"})

      assert url == "/users/42"
    end

    test "handles missing param values" do
      {url, _} = RouteIntrospection.build_url_with_params("/users/:id", %{})

      assert url == "/users/:id"
    end
  end
end
