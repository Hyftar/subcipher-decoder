defmodule Subcipher.Util do
  @moduledoc "Small helpers shared across the app."

  @doc """
  Wraps `value` in a tuple tagged `tag`, so a pipeline can end with it:

      socket
      |> assign(mode: mode)
      |> wrap(:noreply)
      #=> {:noreply, socket}
  """
  def wrap(value, tag), do: {tag, value}
end
