if Code.ensure_loaded?(Ecto) do
  defmodule Ectomancer.Expose.Handlers do
    @moduledoc false

    @doc false
    def select(action, config) do
      repo_module = config.repo
      preload = config.preload

      cond do
        action == :upsert ->
          generate_upsert_handler(repo_module, config)

        action in [:batch_create, :batch_update, :batch_destroy] ->
          generate_batch_handler(repo_module, config, action)

        list_action?(action) ->
          select_preload_handler(repo_module, preload, config, action)

        true ->
          extra = if config.associations, do: [associations: config.associations], else: []
          generate_simple_handler(repo_module, preload, false, config, action, extra)
      end
    end

    defp list_action?(action), do: action in [:list, :get]

    defp select_preload_handler(repo_module, preload, config, action) do
      has_preload = preload != []
      has_preloadable = config.preloadable != false

      cond do
        has_preloadable and config.preloadable == :all ->
          generate_handler_with_all_preloadable(repo_module, preload, has_preload, config, action)

        has_preloadable and is_list(config.preloadable) ->
          generate_handler_with_specific_preloadable(
            repo_module,
            preload,
            has_preload,
            config,
            action
          )

        true ->
          generate_simple_handler(repo_module, preload, has_preload, config, action)
      end
    end

    defp generate_simple_handler(
           repo_module,
           preload,
           has_preload,
           config,
           action,
           extra_opts \\ []
         ) do
      preload_expr =
        if has_preload do
          quote do: opts = Keyword.put(opts, :preload, unquote(preload))
        else
          quote do: :ok
        end

      repo_expr =
        if repo_module do
          quote do: opts = Keyword.put(opts, :repo, unquote(repo_module))
        else
          quote do: :ok
        end

      extra_expr =
        if extra_opts != [] do
          Enum.map(extra_opts, fn {key, value} ->
            quote do
              opts = Keyword.put(opts, unquote(key), unquote(Macro.escape(value)))
            end
          end)
          |> case do
            [] -> quote(do: :ok)
            [single] -> single
            multiple -> {:__block__, [], multiple}
          end
        else
          quote do: :ok
        end

      quote do
        fn params, actor, scope ->
          opts = unquote(scope_expr(config.scope))
          unquote(preload_expr)
          unquote(extra_expr)
          unquote(repo_expr)
          apply(Ectomancer.Repo, unquote(action), [unquote(config.schema), params, opts])
        end
      end
    end

    defp generate_upsert_handler(repo_module, config) do
      conflict_target = config.conflict_target
      on_conflict = config.on_conflict

      repo_expr =
        if repo_module do
          quote do: opts = Keyword.put(opts, :repo, unquote(repo_module))
        else
          quote do: :ok
        end

      quote do
        fn params, actor, scope ->
          opts = unquote(scope_expr(config.scope))

          opts =
            opts ++
              [
                conflict_target: unquote(conflict_target),
                on_conflict: unquote(on_conflict)
              ]

          unquote(repo_expr)
          Ectomancer.Repo.upsert(unquote(config.schema), params, opts)
        end
      end
    end

    defp generate_batch_handler(repo_module, config, action) do
      repo_expr =
        if repo_module do
          quote do: opts = Keyword.put(opts, :repo, unquote(repo_module))
        else
          quote do: :ok
        end

      quote do
        fn params, actor, scope ->
          opts = unquote(scope_expr(config.scope))
          opts = Keyword.put(opts, :batch_size, unquote(config.batch_size))
          unquote(repo_expr)
          apply(Ectomancer.Repo, unquote(action), [unquote(config.schema), params, opts])
        end
      end
    end

    defp generate_handler_with_all_preloadable(
           repo_module,
           preload,
           has_preload,
           config,
           action
         ) do
      assoc_names = Enum.map(config.introspection.associations, &Atom.to_string(&1.field))

      preload_expr =
        if has_preload do
          quote do: opts = Keyword.put(opts, :preload, unquote(preload))
        else
          quote do: :ok
        end

      repo_expr =
        if repo_module do
          quote do: opts = Keyword.put(opts, :repo, unquote(repo_module))
        else
          quote do: :ok
        end

      quote do
        fn params, actor, scope ->
          opts = unquote(scope_expr(config.scope))
          unquote(preload_expr)
          {include, clean_params} = Map.pop(params, "include", nil)
          opts = Ectomancer.Repo.validate_includes(include, unquote(assoc_names), opts)
          unquote(repo_expr)
          apply(Ectomancer.Repo, unquote(action), [unquote(config.schema), clean_params, opts])
        end
      end
    end

    defp generate_handler_with_specific_preloadable(
           repo_module,
           preload,
           has_preload,
           config,
           action
         ) do
      allowed = Enum.map(config.preloadable, &to_string/1)

      preload_expr =
        if has_preload do
          quote do: opts = Keyword.put(opts, :preload, unquote(preload))
        else
          quote do: :ok
        end

      repo_expr =
        if repo_module do
          quote do: opts = Keyword.put(opts, :repo, unquote(repo_module))
        else
          quote do: :ok
        end

      quote do
        fn params, actor, scope ->
          opts = unquote(scope_expr(config.scope))
          unquote(preload_expr)
          {include, clean_params} = Map.pop(params, "include", nil)
          opts = Ectomancer.Repo.validate_includes(include, unquote(allowed), opts)
          unquote(repo_expr)
          apply(Ectomancer.Repo, unquote(action), [unquote(config.schema), clean_params, opts])
        end
      end
    end

    defp scope_expr(nil) do
      quote(do: [scope: scope])
    end

    defp scope_expr(config_scope) do
      quote(do: [scope: Ectomancer.Scope.compose(scope, actor, unquote(config_scope))])
    end

    @doc false
    def wrap_with_field_auth(base_handler, field_auth_fn) do
      quote do
        fn params, actor, scope ->
          with {:ok, data} <- unquote(base_handler).(params, actor, scope) do
            {:ok, Ectomancer.FieldAuth.filter_fields(data, actor, unquote(field_auth_fn))}
          end
        end
      end
    end

    @doc false
    def wrap_with_field_filter(base_handler, allowed_fields) do
      quote do
        fn params, actor, scope ->
          with {:ok, data} <- unquote(base_handler).(params, actor, scope) do
            {:ok, Ectomancer.Output.filter_fields(data, unquote(allowed_fields))}
          end
        end
      end
    end
  end
else
  defmodule Ectomancer.Expose.Handlers do
    @moduledoc false
  end
end
