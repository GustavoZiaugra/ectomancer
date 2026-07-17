if Code.ensure_loaded?(Ecto) do
  defmodule Ectomancer.Expose.Params do
    @moduledoc false

    @filter_suffixes %{
      string: ~w(contains icontains not in),
      number: ~w(gt gte lt lte not in),
      datetime: ~w(gt gte lt lte not)
    }

    @number_types [:integer, :float, :decimal, :id]
    @datetime_types [
      :date,
      :time,
      :time_usec,
      :naive_datetime,
      :naive_datetime_usec,
      :utc_datetime,
      :utc_datetime_usec
    ]

    @doc false
    def generate(action, config) do
      Ectomancer.Expose.Params.generate_params(action, config)
    end

    def generate_params(:list, config) do
      base_params = build_list_base_params(config.exposed_fields, config.introspection.types)

      suffix_params =
        build_list_filter_params(config.filterable_fields, config.introspection.types)

      meta_params =
        if config.soft_delete do
          quote do
            param(:order_by, :string)
            param(:order_dir, :string)
            param(:limit, :integer)
            param(:offset, :integer)
            param(:include_deleted, :boolean)
            unquote(include_param(config.preloadable))
          end
        else
          quote do
            param(:order_by, :string)
            param(:order_dir, :string)
            param(:limit, :integer)
            param(:offset, :integer)
            unquote(include_param(config.preloadable))
          end
        end

      all_params = base_params ++ suffix_params

      case all_params do
        [] ->
          meta_params

        _ ->
          {:__block__, [], all_params ++ elem(meta_params, 2)}
      end
    end

    def generate_params(:get, config) do
      pk_field = hd(config.introspection.primary_key)

      pk_type =
        Ectomancer.Expose.get_ecto_type_for_param(Map.get(config.introspection.types, pk_field))

      if config.soft_delete do
        quote do
          param(unquote(pk_field), unquote(pk_type), required: true)
          param(:include_deleted, :boolean)
          unquote(include_param(config.preloadable))
        end
      else
        quote do
          param(unquote(pk_field), unquote(pk_type), required: true)
          unquote(include_param(config.preloadable))
        end
      end
    end

    def generate_params(:create, config) do
      build_param_block(config.writable_fields, config.introspection.types)
    end

    def generate_params(:update, config) do
      pk_field = hd(config.introspection.primary_key)

      pk_type =
        Ectomancer.Expose.get_ecto_type_for_param(Map.get(config.introspection.types, pk_field))

      writable_params = build_param_block(config.writable_fields, config.introspection.types)

      quote do
        param(unquote(pk_field), unquote(pk_type), required: true)
        unquote(writable_params)
      end
    end

    def generate_params(:upsert, config) do
      build_param_block(config.writable_fields, config.introspection.types)
    end

    def generate_params(:destroy, config) do
      pk_field = hd(config.introspection.primary_key)

      pk_type =
        Ectomancer.Expose.get_ecto_type_for_param(Map.get(config.introspection.types, pk_field))

      quote do
        param(unquote(pk_field), unquote(pk_type), required: true)
      end
    end

    def generate_params(:restore, config) do
      pk_field = hd(config.introspection.primary_key)

      pk_type =
        Ectomancer.Expose.get_ecto_type_for_param(Map.get(config.introspection.types, pk_field))

      quote do
        param(unquote(pk_field), unquote(pk_type), required: true)
      end
    end

    def generate_params(:batch_create, _config) do
      quote do
        param(:records, {:array, :map},
          required: true,
          description: "Array of records to create"
        )
      end
    end

    def generate_params(:batch_update, _config) do
      quote do
        param(:records, {:array, :map},
          required: true,
          description: "Array of records with id and fields to update"
        )
      end
    end

    def generate_params(:batch_destroy, _config) do
      quote do
        param(:ids, :list,
          required: true,
          description: "Array of record IDs to delete"
        )
      end
    end

    defp build_list_base_params(fields, types) do
      Enum.map(fields, fn field ->
        type = Map.get(types, field)
        build_single_param(field, type)
      end)
    end

    defp build_list_filter_params(fields, types) do
      Enum.flat_map(fields, fn field ->
        type = Map.get(types, field)
        build_suffix_params(field, type)
      end)
    end

    defp build_single_param(field, type) do
      param_type = Ectomancer.Expose.get_ecto_type_for_param(type)

      quote do
        param(unquote(field), unquote(param_type))
      end
    end

    defp build_suffix_params(field, type) do
      suffixes = suffixes_for_type(type)

      Enum.map(suffixes, fn suffix ->
        suffixed_name = :"#{field}_#{suffix}"
        param_type = suffix_param_type(suffix, type)

        quote do
          param(unquote(suffixed_name), unquote(param_type))
        end
      end)
    end

    defp suffixes_for_type(type) when type in @number_types, do: @filter_suffixes.number
    defp suffixes_for_type(type) when type in @datetime_types, do: @filter_suffixes.datetime
    defp suffixes_for_type(:string), do: @filter_suffixes.string
    defp suffixes_for_type(:binary_id), do: ["not", "in"]
    defp suffixes_for_type(Ecto.UUID), do: ["not", "in"]
    defp suffixes_for_type(:boolean), do: ["not"]
    defp suffixes_for_type(_), do: []

    defp suffix_param_type("in", _type), do: :list
    defp suffix_param_type(_suffix, type), do: Ectomancer.Expose.get_ecto_type_for_param(type)

    defp include_param(false), do: nil

    defp include_param(_preloadable) do
      quote do
        param(:include, :list)
      end
    end

    def build_param_block(fields, types) do
      fields
      |> Enum.map(fn field ->
        type = Map.get(types, field)
        param_type = Ectomancer.Expose.get_ecto_type_for_param(type)

        quote do
          param(unquote(field), unquote(param_type))
        end
      end)
      |> case do
        [] -> quote(do: :ok)
        [single] -> single
        multiple -> {:__block__, [], multiple}
      end
    end
  end
else
  defmodule Ectomancer.Expose.Params do
    @moduledoc false
  end
end
