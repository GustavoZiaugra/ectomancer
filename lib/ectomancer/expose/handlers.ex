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
          generate_batch_handler(repo_module, config.schema, action, config.batch_size)

        list_action?(action) ->
          select_preload_handler(repo_module, preload, config, action)

        true ->
          generate_simple_handler(repo_module, preload, false, config.schema, action)
      end
    end

    defp list_action?(action), do: action in [:list, :get]

    defp select_preload_handler(repo_module, preload, config, action) do
      has_preload = preload != []
      has_preloadable = config.preloadable != false

      cond do
        has_preloadable and config.preloadable == :all ->
          generate_handler_with_all_preloadable(
            repo_module,
            preload,
            has_preload,
            config.introspection,
            config.schema,
            action
          )

        has_preloadable and is_list(config.preloadable) ->
          generate_handler_with_specific_preloadable(
            repo_module,
            preload,
            has_preload,
            config.preloadable,
            config.schema,
            action
          )

        true ->
          generate_simple_handler(repo_module, preload, has_preload, config.schema, action)
      end
    end

    defp generate_simple_handler(repo_module, preload, has_preload, schema, action) do
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
        fn params, _actor, scope ->
          opts = [scope: scope]
          unquote(preload_expr)
          unquote(repo_expr)
          apply(Ectomancer.Repo, unquote(action), [unquote(schema), params, opts])
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
        fn params, _actor, scope ->
          opts = [
            scope: scope,
            conflict_target: unquote(conflict_target),
            on_conflict: unquote(on_conflict)
          ]

          unquote(repo_expr)
          Ectomancer.Repo.upsert(unquote(config.schema), params, opts)
        end
      end
    end

    defp generate_batch_handler(repo_module, schema, action, batch_size) do
      repo_expr =
        if repo_module do
          quote do: opts = Keyword.put(opts, :repo, unquote(repo_module))
        else
          quote do: :ok
        end

      quote do
        fn params, _actor, scope ->
          opts = [scope: scope, batch_size: unquote(batch_size)]
          unquote(repo_expr)
          apply(Ectomancer.Repo, unquote(action), [unquote(schema), params, opts])
        end
      end
    end

    defp generate_handler_with_all_preloadable(
           repo_module,
           preload,
           has_preload,
           introspection,
           schema,
           action
         ) do
      assoc_names = Enum.map(introspection.associations, &Atom.to_string(&1.field))

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
        fn params, _actor, scope ->
          opts = [scope: scope]
          unquote(preload_expr)
          {include, clean_params} = Map.pop(params, "include", nil)
          opts = Ectomancer.Repo.validate_includes(include, unquote(assoc_names), opts)
          unquote(repo_expr)
          apply(Ectomancer.Repo, unquote(action), [unquote(schema), clean_params, opts])
        end
      end
    end

    defp generate_handler_with_specific_preloadable(
           repo_module,
           preload,
           has_preload,
           allowed,
           schema,
           action
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

      quote do
        fn params, _actor, scope ->
          opts = [scope: scope]
          unquote(preload_expr)
          {include, clean_params} = Map.pop(params, "include", nil)
          opts = Ectomancer.Repo.validate_includes(include, unquote(allowed), opts)
          unquote(repo_expr)
          apply(Ectomancer.Repo, unquote(action), [unquote(schema), clean_params, opts])
        end
      end
    end

    def wrap_with_field_auth(base_handler, field_auth_fn) do
      quote do
        fn params, actor, scope ->
          with {:ok, data} <- unquote(base_handler).(params, actor, scope) do
            {:ok, Ectomancer.FieldAuth.filter_fields(data, actor, unquote(field_auth_fn))}
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
