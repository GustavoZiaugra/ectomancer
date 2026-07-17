if Code.ensure_loaded?(Ecto) do
  defmodule Ectomancer.Repo.Filtering do
    @moduledoc false

    import Ecto.Query

    alias Ectomancer.SchemaIntrospection

    @meta_keys ~w(order_by order_dir limit offset include_deleted)

    @doc false
    def extract_meta_params(params) do
      {meta, filters} =
        Enum.split_with(params, fn {key, _} -> to_string(key) in @meta_keys end)

      {Map.new(meta, fn {k, v} -> {to_string(k), v} end), Map.new(filters)}
    end

    @doc false
    def build_filter_query(schema_module, params, fields) do
      base_query = from(r in schema_module)

      Enum.reduce(params, base_query, fn {field_str, value}, query ->
        {field, operator} = parse_filter_key(to_string(field_str))

        if field in fields do
          apply_filter(query, field, operator, value)
        else
          query
        end
      end)
    end

    @doc false
    def parse_filter_key(key) do
      suffixes = ~w(_gte _gt _lte _lt _contains _icontains _in _not)

      Enum.find_value(suffixes, {String.to_atom(key), :eq}, fn suffix ->
        if String.ends_with?(key, suffix) do
          base = String.replace_trailing(key, suffix, "")
          op = suffix |> String.trim_leading("_") |> String.to_atom()
          {String.to_atom(base), op}
        end
      end)
    end

    defp apply_filter(query, field, :eq, value) do
      where(query, [r], field(r, ^field) == ^value)
    end

    defp apply_filter(query, field, :gt, value) do
      where(query, [r], field(r, ^field) > ^value)
    end

    defp apply_filter(query, field, :gte, value) do
      where(query, [r], field(r, ^field) >= ^value)
    end

    defp apply_filter(query, field, :lt, value) do
      where(query, [r], field(r, ^field) < ^value)
    end

    defp apply_filter(query, field, :lte, value) do
      where(query, [r], field(r, ^field) <= ^value)
    end

    defp apply_filter(query, field, :not, value) do
      where(query, [r], field(r, ^field) != ^value)
    end

    defp apply_filter(query, field, :contains, value) do
      pattern = "%#{sanitize_like(value)}%"
      where(query, [r], like(field(r, ^field), ^pattern))
    end

    defp apply_filter(query, field, :icontains, value) do
      pattern = "%#{sanitize_like(value)}%" |> String.downcase()
      where(query, [r], like(fragment("LOWER(?)", field(r, ^field)), ^pattern))
    end

    defp apply_filter(query, field, :in, value) when is_list(value) do
      where(query, [r], field(r, ^field) in ^value)
    end

    defp apply_filter(query, _field, :in, _value), do: query

    @doc false
    def sanitize_like(value) do
      value
      |> to_string()
      |> String.replace("\\", "\\\\")
      |> String.replace("%", "\\%")
      |> String.replace("_", "\\_")
    end

    @doc false
    def apply_ordering(query, meta, fields) do
      case meta do
        %{"order_by" => order_field} ->
          field = String.to_atom(to_string(order_field))
          dir = parse_order_dir(Map.get(meta, "order_dir", "asc"))

          if field in fields do
            order_by(query, [r], [{^dir, field(r, ^field)}])
          else
            query
          end

        _ ->
          query
      end
    end

    @doc false
    def parse_order_dir(dir) when is_binary(dir) do
      case String.downcase(dir) do
        "desc" -> :desc
        _ -> :asc
      end
    end

    @doc false
    def parse_order_dir(_), do: :asc

    @doc false
    def apply_pagination(query, meta, opts) do
      limit_val = parse_int(Map.get(meta, "limit")) || Keyword.get(opts, :limit, 100)
      offset_val = parse_int(Map.get(meta, "offset")) || Keyword.get(opts, :offset, 0)

      limit_val = min(limit_val, 100)

      query
      |> limit(^limit_val)
      |> offset(^offset_val)
    end

    @doc false
    def parse_int(nil), do: nil
    @doc false
    def parse_int(val) when is_integer(val), do: val
    @doc false
    def parse_int(val) when is_binary(val) do
      case Integer.parse(val) do
        {int, ""} -> int
        _ -> nil
      end
    end

    @doc false
    def parse_int(_), do: nil

    @doc false
    def apply_soft_delete_filter(query, schema_module, meta_params) do
      sd_field = SchemaIntrospection.soft_delete_field(schema_module)

      if sd_field && !Map.get(meta_params, "include_deleted", false) do
        where(query, [r], is_nil(field(r, ^sd_field)))
      else
        query
      end
    end

    @doc false
    def apply_scope(query, nil), do: query
    def apply_scope(query, scope_fn) when is_function(scope_fn, 1), do: scope_fn.(query)
  end
else
  defmodule Ectomancer.Repo.Filtering do
    @moduledoc false
  end
end
