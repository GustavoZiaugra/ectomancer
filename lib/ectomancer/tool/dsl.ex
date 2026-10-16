defmodule Ectomancer.Tool.DSL do
  @moduledoc """
  DSL macros for tool definition.

  These macros are parsed at compile time by `Ectomancer.Tool` and do not
  execute at runtime.
  """

  defmacro description(_text), do: quote(do: nil)
  defmacro param(_name, _type, _opts \\ []), do: quote(do: nil)
  defmacro handle(do: _block), do: quote(do: nil)
end
