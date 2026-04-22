defmodule Ectomancer.Installer.DependencyChecker do
  @moduledoc """
  Checks for required and optional dependencies in the project.
  """

  @required_deps [:ecto, :plug]
  @optional_deps [:phoenix, :oban]

  @doc """
  Check if all required dependencies are present in mix.exs.

  Returns :ok if all required deps are found, or {:error, [missing_deps]} if any are missing.
  """
  @spec check_required() :: :ok | {:error, [atom()]}
  def check_required do
    missing = @required_deps |> Enum.reject(&dep_exists?/1)
    if missing == [], do: :ok, else: {:error, missing}
  end

  @doc """
  Check which optional dependencies are present in mix.exs.

  Returns a list of found optional dependencies.
  """
  @spec check_optional() :: [atom()]
  def check_optional do
    @optional_deps |> Enum.filter(&dep_exists?/1)
  end

  @doc """
  Generate a friendly error message for missing dependencies.

  Returns a formatted string listing the missing dependencies and how to add them.
  """
  @spec missing_deps_message([atom()]) :: String.t()
  def missing_deps_message(missing_deps) do
    """
    Missing required dependencies:
    #{Enum.map_join(missing_deps, "\n", &"  - #{&1}")}

    Add these to your mix.exs deps function, then run `mix deps.get` and try again.
    Example:
        {:ecto, \"~> 3.12\"},
        {:plug, \"~> 1.16\"}
    """
  end

  @doc """
  Check if a specific dependency exists in mix.exs.

  Returns true if the dependency is found, false otherwise.
  """
  @spec dep_exists?(atom()) :: boolean
  def dep_exists?(dep) do
    case File.read("mix.exs") do
      {:ok, content} ->
        # Look for the dependency in the deps list
        # Standard format: {:dep, ...}
        dep_string = Atom.to_string(dep)
        String.contains?(content, "{:#{dep_string},")

      _error ->
        false
    end
  end
end
