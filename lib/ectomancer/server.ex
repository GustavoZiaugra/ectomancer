defmodule Ectomancer.Server do
  @moduledoc """
  Server utilities for Ectomancer.

  This module provides helper functions for working with the actor
  in tool handlers. The actor is automatically extracted by
  Ectomancer.Plug and made available in frame.assigns.

  ## Actor Access

  In tool handlers, access the actor via:

      actor = Ectomancer.Server.get_actor(frame)

  Or directly from frame.assigns:

      actor = frame.assigns[:ectomancer_actor]
  """

  alias Anubis.Server.Frame

  @doc """
  Gets the actor from a frame's assigns.

  ## Examples

      actor = Ectomancer.Server.get_actor(frame)
  """
  @spec get_actor(Frame.t()) :: any()
  def get_actor(frame) do
    get_in(frame, [:assigns, :ectomancer_actor])
  end
end
