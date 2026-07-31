if Code.ensure_loaded?(Ecto) do
  defmodule Ectomancer.Repo.Filtering do
    @moduledoc false

    import Ecto.Query

    alias Ectomancer.SchemaIntrospection

    @meta_keys ~w(order_by order_dir limit offset include_deleted)

    # Suffix -> operator. Ordered longest-first so compound suffixes match
    # before their prefixes would be misread (e.g. `_gte` before `_gt`).
    @filter_ops [
      {"_gte", :gte},
      {"_lte", :lte},
      {"_contains", :contains},
      {"_icontains", :icontains},
      {"_gt", :gt},
      {"_lt", :lt},
      {"_in", :in},
      {"_not", :not}
    ]

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
        {field_name, operator} = parse_filter_key(to_string(field_str))

        case find_field(fields, field_name) do
          nil -> query
          field -> apply_filter(query, field, operator, value)
        end
      end)
    end

    @doc false
    def parse_filter_key(key) do
      case Enum.find(@filter_ops, fn {suffix, _op} -> String.ends_with?(key, suffix) end) do
        nil -> {key, :eq}
        {suffix, op} -> {String.replace_trailing(key, suffix, ""), op}
      end
    end

    # Resolves a caller-supplied field name against the schema's fields without
    # minting new atoms (see #142 — remote atom-table exhaustion).
    defp find_field(fields, name) do
      Enum.find(fields, &(Atom.to_string(&1) == name))
    end

    defp apply_filter(query, field, :eq, nil) do
      where(query, [r], is_nil(field(r, ^field)))
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

    defp apply_filter(query, field, :not, nil) do
      where(query, [r], not is_nil(field(r, ^field)))
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
          case find_field(fields, to_string(order_field)) do
            nil ->
              query

            field ->
              dir = parse_order_dir(Map.get(meta, "order_dir", "asc"))
              order_by(query, [r], [{^dir, field(r, ^field)}])
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

      limit_val = min(limit_val, max_limit())

      query
      |> limit(^limit_val)
      |> offset(^offset_val)
    end

    @doc false
    def max_limit do
      Application.get_env(:ectomancer, :max_limit, 100)
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
