defmodule SubcipherWeb.AlgorithmLive.Events.Input do
  @moduledoc """
  Events of what an algorithm encodes or decodes: the text typed, or the
  symbols composed with the keyboard of its symbol key.
  """
  import Phoenix.Component, only: [assign: 2, update: 3]
  import Subcipher.Util, only: [wrap: 2]
  import SubcipherWeb.AlgorithmLive.Assigns, only: [assign_trace: 1]

  def handle_event("input", %{"text" => text}, socket) do
    socket
    |> update(:texts, &Map.put(&1, socket.assigns.mode, text))
    |> assign_trace()
    |> wrap(:noreply)
  end

  def handle_event("add_symbol", %{"index" => index}, socket) do
    socket
    |> add_token({:symbol, String.to_integer(index)})
    |> wrap(:noreply)
  end

  # Whitespace keys send a name: raw whitespace doesn't survive HTML
  # attributes reliably (a "\n" in a ~H template stays a backslash and an n).
  def handle_event("add_char", %{"char" => "space"}, socket),
    do: socket |> add_token({:char, " "}) |> wrap(:noreply)

  def handle_event("add_char", %{"char" => "newline"}, socket),
    do: socket |> add_token({:char, "\n"}) |> wrap(:noreply)

  def handle_event("add_char", _params, socket), do: wrap(socket, :noreply)

  def handle_event("backspace", _params, socket) do
    socket
    |> update(:symbols, &Enum.drop(&1, -1))
    |> assign_trace()
    |> wrap(:noreply)
  end

  def handle_event("clear", _params, socket) do
    socket
    |> assign(symbols: [])
    |> assign_trace()
    |> wrap(:noreply)
  end

  defp add_token(socket, token) do
    socket
    |> update(:symbols, &(&1 ++ [token]))
    |> assign_trace()
  end
end
