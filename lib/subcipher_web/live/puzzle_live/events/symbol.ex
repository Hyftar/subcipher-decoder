defmodule SubcipherWeb.PuzzleLive.Events.Symbol do
  @moduledoc """
  Events changing the symbols of a pictures puzzle: their letters, ignoring,
  merging, splitting and regrouping them.
  """
  import Phoenix.Component, only: [assign: 2]
  import Subcipher.Util, only: [wrap: 2]
  import Phoenix.LiveView, only: [put_flash: 3]

  alias Subcipher.Ciphers

  import SubcipherWeb.PuzzleLive.Assigns, only: [load: 2, reload: 1]

  def handle_event("assign", %{"symbol_id" => id, "letter" => letter}, socket) do
    case socket.assigns.symbols[String.to_integer(id)] do
      nil -> wrap(socket, :noreply)
      symbol -> socket |> assign_letter(symbol, letter) |> wrap(:noreply)
    end
  end

  def handle_event("toggle_ignore", %{"id" => id}, socket) do
    symbol = Map.fetch!(socket.assigns.symbols, String.to_integer(id))
    {:ok, _} = Ciphers.set_ignored(symbol, !symbol.ignored)
    socket |> reload() |> wrap(:noreply)
  end

  def handle_event("start_merge", _params, socket) do
    socket |> assign(merging: socket.assigns.selected_symbol_id != nil) |> wrap(:noreply)
  end

  def handle_event("cancel_merge", _params, socket) do
    socket |> assign(merging: false) |> wrap(:noreply)
  end

  def handle_event("detach", _params, socket) do
    glyph = Enum.find(socket.assigns.puzzle.glyphs, &(&1.id == socket.assigns.selected_glyph_id))

    case glyph && Ciphers.detach_glyph(glyph) do
      {:ok, symbol} ->
        socket
        |> assign(selected_symbol_id: symbol.id)
        |> put_flash(:info, "This glyph is now a symbol of its own.")
        |> reload()
        |> wrap(:noreply)

      _ ->
        wrap(socket, :noreply)
    end
  end

  def handle_event("reset_letters", _params, socket) do
    :ok = Ciphers.reset_letters(socket.assigns.puzzle)
    socket |> reload() |> wrap(:noreply)
  end

  def handle_event("regroup", %{"tolerance" => tolerance}, socket) do
    with {t, ""} <- Integer.parse(tolerance),
         true <- t in 5..150,
         {:ok, puzzle} <- Ciphers.regroup(socket.assigns.puzzle, t / 1000) do
      socket
      |> assign(selected_symbol_id: nil, selected_glyph_id: nil, merging: false)
      |> load(puzzle)
      |> put_flash(:info, "Symbols regrouped: #{length(puzzle.symbols)} distinct symbols.")
      |> wrap(:noreply)
    else
      _ -> socket |> put_flash(:error, "Could not regroup the symbols.") |> wrap(:noreply)
    end
  end

  @doc "Substitutes `symbol` with `letter` (nil clears it)."
  def assign_letter(socket, symbol, letter) do
    case Ciphers.assign_letter(symbol, letter) do
      {:ok, _} -> reload(socket)
      {:error, _} -> put_flash(socket, :error, "A substitution is at most 3 characters.")
    end
  end
end
