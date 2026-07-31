defmodule Ectomancer.Output do
  @moduledoc """
  Sanitizes and serializes Ectomancer tool results into JSON-safe output.

  Ecto structs are converted to plain maps, Ecto internals (`__meta__`,
  `#Ecto.Association.NotLoaded<>`) are removed or replaced with `null`, and
  datetime/decimal values are rendered as ISO-8601 strings so that MCP clients
  receive valid, parseable JSON.

  Field filtering is applied recursively so `only:`/`except:` redaction also
  reaches nested records (e.g. batch results and preloaded associations).
  """

  @doc """
  Recursively filters the fields of Ecto structs to the given allowlist.

  Works on single structs, lists, plain maps, paginated results, and batch
  result maps. Non-struct values (strings, numbers, datetimes) pass through
  unchanged.
  """
  @spec filter_fields(term(), [atom()]) :: term()
  def filter_fields(term, allowed) when is_list(allowed) do
    do_filter_fields(term, allowed)
  end

  @doc """
  Encodes a value as a JSON string, sanitizing Ecto structs along the way.

  - Structs are converted to maps (keys as strings), dropping `__meta__`.
  - `Ecto.Association.NotLoaded` becomes `null`.
  - `Date`/`Time`/`NaiveDateTime`/`DateTime` become ISO-8601 strings.
  - `Decimal` becomes a string.
  - Plain binaries are returned verbatim (not quoted).
  """
  @spec encode!(term()) :: String.t()
  def encode!(data) do
    case to_json_value(data) do
      binary when is_binary(binary) -> binary
      json_value -> Jason.encode!(json_value)
    end
  end

  defp do_filter_fields(%Ecto.Association.NotLoaded{}, _allowed), do: nil

  defp do_filter_fields(%{__struct__: module} = struct, allowed) when is_atom(module) do
    struct
    |> Map.from_struct()
    |> Map.drop([:__meta__])
    |> Enum.filter(fn {field, _value} -> field in allowed end)
    |> Map.new(fn {field, value} -> {field, do_filter_fields(value, allowed)} end)
  end

  defp do_filter_fields(value, allowed) when is_list(value) do
    Enum.map(value, &do_filter_fields(&1, allowed))
  end

  defp do_filter_fields(%{__struct__: _} = struct, _allowed), do: struct

  defp do_filter_fields(map, allowed) when is_map(map) do
    Map.new(map, fn {key, value} -> {key, do_filter_fields(value, allowed)} end)
  end

  defp do_filter_fields(value, _allowed), do: value

  defp to_json_value(%Ecto.Association.NotLoaded{}), do: nil
  defp to_json_value(%Ecto.Schema.Metadata{}), do: nil
  defp to_json_value(%Date{} = value), do: Date.to_iso8601(value)
  defp to_json_value(%Time{} = value), do: Time.to_iso8601(value)
  defp to_json_value(%NaiveDateTime{} = value), do: NaiveDateTime.to_iso8601(value)
  defp to_json_value(%DateTime{} = value), do: DateTime.to_iso8601(value)
  defp to_json_value(%Decimal{} = value), do: Decimal.to_string(value)

  defp to_json_value(%{__struct__: module} = struct) when is_atom(module) do
    struct
    |> Map.from_struct()
    |> Map.drop([:__meta__])
    |> Map.new(fn {key, value} -> {key_to_string(key), to_json_value(value)} end)
  end

  defp to_json_value(value) when is_list(value), do: Enum.map(value, &to_json_value/1)

  defp to_json_value(map) when is_map(map) do
    Map.new(map, fn {key, value} -> {key_to_string(key), to_json_value(value)} end)
  end

  defp to_json_value(value), do: value

  defp key_to_string(key) when is_atom(key), do: Atom.to_string(key)
  defp key_to_string(key) when is_binary(key), do: key
  defp key_to_string(key), do: key
end
