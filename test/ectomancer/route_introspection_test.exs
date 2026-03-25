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
end
