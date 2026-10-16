defmodule Ectomancer.FieldAuth do
  @moduledoc """
  Field-level authorization for Ectomancer tools.

  Allows filtering record fields based on actor permissions after a tool
  executes. Field auth is applied as a response transform — the row data
  itself is unaffected, only the returned fields are filtered. The one
  query-level effect: `:list` ordering (`order_by`) is restricted to fields
  the actor is allowed to see, so a denied field cannot control row order
  and leak relative values through the ordering.

  ## Usage

      expose MyApp.Accounts.User,
        field_authorize: fn actor, field ->
          case field do
            :password_hash -> actor.role == :admin
            :salary -> actor.role == :admin
            :email -> true
            _ -> actor != nil
          end
        end

  The callback receives the actor and the field name (as an atom) and
  should return `true` (allow) or `false` (deny).
  """

  @doc """
  Filters fields from a tool result based on an authorization callback.

  Works with single structs, lists of structs, and plain maps.

  ## Examples

      iex> filter_fields(%User{email: "a@b.com", password_hash: "secret"}, %{role: :admin}, fn _, _ -> true end)
      %{email: "a@b.com", password_hash: "secret"}

      iex> filter_fields(%User{email: "a@b.com", password_hash: "secret"}, %{role: :user}, fn
      ...>   _actor, :password_hash -> false
      ...>   _actor, _ -> true
      ...> end)
      %{email: "a@b.com"}
  """
  @spec filter_fields(any(), any(), function()) :: any()
  def filter_fields(data, _actor, nil), do: data
  def filter_fields(data, _actor, auth_fn) when not is_function(auth_fn, 2), do: data

  def filter_fields(data, actor, auth_fn) when is_list(data) do
    Enum.map(data, &filter_fields(&1, actor, auth_fn))
  end

  def filter_fields(%{__struct__: _} = record, actor, auth_fn) do
    record
    |> Map.from_struct()
    |> Enum.filter(fn {field, _value} -> auth_fn.(actor, field) end)
    |> Map.new()
  end

  def filter_fields(%{data: data, pagination: _} = paginated, actor, auth_fn) do
    %{paginated | data: filter_fields(data, actor, auth_fn)}
  end

  def filter_fields(data, _actor, _auth_fn), do: data

  @doc """
  Returns whether `field` is allowed for `actor` under the authorization
  callback. Mirrors the truthiness used by `filter_fields/3`.

  Used to restrict `order_by` to fields the actor may actually see, so a
  denied field cannot control row ordering.
  """
  @spec field_allowed?(any(), atom(), function() | nil) :: boolean()
  def field_allowed?(_actor, _field, nil), do: true
  def field_allowed?(_actor, _field, auth_fn) when not is_function(auth_fn, 2), do: true

  def field_allowed?(actor, field, auth_fn) do
    !!auth_fn.(actor, field)
  end
end
