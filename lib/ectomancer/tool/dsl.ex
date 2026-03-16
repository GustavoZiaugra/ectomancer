defmodule Ectomancer.Tool.DSL do
  @moduledoc """
  DSL macros for tool definition.
  These are parsed at compile time and do not execute at runtime.
  """

  # Parsed at macro level
  defmacro description(_text), do: quote(do: nil)
  # Parsed at macro level
  defmacro param(_name, _type, _opts \\ []), do: quote(do: nil)
  # Parsed at macro level - block contains the actual handler
  defmacro handle(do: _block), do: quote(do: nil)
end
