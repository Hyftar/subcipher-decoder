defmodule SubcipherWeb.PuzzleLive.Events.Selection do
  @moduledoc """
  Selecting symbols and glyphs of a pictures puzzle, with the mouse or the
  keyboard (see the `.CipherKeys` hook); typing a letter substitutes the
  selected symbol. Clicking a symbol while merging merges it.
  """
  import Phoenix.Component, only: [assign: 2]
  import Subcipher.Util, only: [wrap: 2]
  import Phoenix.LiveView, only: [put_flash: 3]

  alias Subcipher.Ciphers

  import SubcipherWeb.PuzzleLive.Assigns, only: [reload: 1]
  import SubcipherWeb.PuzzleLive.Events.Symbol, only: [assign_letter: 3]

  def handle_event("select_glyph", %{"id" => id}, socket) do
    case Enum.find(socket.assigns.puzzle.glyphs, &(to_string(&1.id) == id)) do
      nil -> wrap(socket, :noreply)
      glyph -> socket |> select(glyph.symbol_id, glyph.id) |> wrap(:noreply)
    end
  end

  def handle_event("select_symbol", %{"id" => id}, socket) do
    case Enum.find(socket.assigns.puzzle.symbols, &(to_string(&1.id) == id)) do
      nil -> wrap(socket, :noreply)
      symbol -> socket |> select(symbol.id, nil) |> wrap(:noreply)
    end
  end

  def handle_event("deselect", _params, socket) do
    socket
    |> assign(selected_symbol_id: nil, selected_glyph_id: nil, merging: false)
    |> wrap(:noreply)
  end

  def handle_event("key", %{"key" => key} = params, socket) do
    handle_key(key, params["shift"] == true, socket)
  end

  # Clicking a symbol while merging merges it into the selected symbol.
  defp select(%{assigns: %{merging: true}} = socket, symbol_id, _glyph_id) do
    %{selected_symbol_id: target_id, symbols: symbols} = socket.assigns

    if symbol_id == target_id do
      assign(socket, merging: false)
    else
      {:ok, _} = Ciphers.merge_symbols(symbols[target_id], symbols[symbol_id])

      socket
      |> assign(merging: false)
      |> put_flash(:info, "Symbols merged.")
      |> reload()
    end
  end

  defp select(socket, symbol_id, glyph_id) do
    assign(socket,
      selected_symbol_id: symbol_id,
      selected_glyph_id: glyph_id,
      edited_glyph_id: nil
    )
  end

  defp handle_key("Escape", _shift, socket) do
    if socket.assigns.merging,
      do: socket |> assign(merging: false) |> wrap(:noreply),
      else: socket |> assign(selected_symbol_id: nil, selected_glyph_id: nil) |> wrap(:noreply)
  end

  # ← / →: previous / next character of the text.
  defp handle_key("ArrowLeft", _shift, socket), do: socket |> move_in_text(-1) |> wrap(:noreply)
  defp handle_key("ArrowRight", _shift, socket), do: socket |> move_in_text(1) |> wrap(:noreply)

  # ↑ / ↓ (and Tab / Shift+Tab): previous / next symbol of the symbol key.
  defp handle_key(key, shift, socket) when key in ~w(ArrowDown ArrowUp Tab) do
    backwards = key == "ArrowUp" or (key == "Tab" and shift)
    socket |> move_in_key(if(backwards, do: -1, else: 1)) |> wrap(:noreply)
  end

  defp handle_key(key, _shift, socket) when key in ~w(Backspace Delete) do
    case selected_symbol(socket) do
      nil -> wrap(socket, :noreply)
      symbol -> socket |> assign_letter(symbol, nil) |> wrap(:noreply)
    end
  end

  defp handle_key(key, _shift, socket) do
    case {selected_symbol(socket), String.length(key)} do
      {%{} = symbol, 1} -> socket |> assign_letter(symbol, key) |> wrap(:noreply)
      _ -> wrap(socket, :noreply)
    end
  end

  defp selected_symbol(socket), do: socket.assigns.symbols[socket.assigns.selected_symbol_id]

  # Moves character by character through the text, in reading order (picture
  # after picture), skipping ignored symbols. Stops at both ends. When a
  # symbol is selected without a specific character (e.g. from the key), the
  # move starts from its first occurrence.
  defp move_in_text(socket, step) do
    %{puzzle: puzzle, symbols: symbols} = socket.assigns
    glyphs = Enum.reject(puzzle.glyphs, &symbols[&1.symbol_id].ignored)
    current = Enum.find_index(glyphs, &(&1.id == socket.assigns.selected_glyph_id))

    target =
      cond do
        glyphs == [] ->
          nil

        current ->
          # Clamped: no wrapping (Enum.at/2 would read negative indexes from the end).
          Enum.at(glyphs, (current + step) |> max(0) |> min(length(glyphs) - 1))

        socket.assigns.selected_symbol_id ->
          Enum.find(glyphs, &(&1.symbol_id == socket.assigns.selected_symbol_id)) ||
            hd(glyphs)

        step > 0 ->
          hd(glyphs)

        true ->
          List.last(glyphs)
      end

    case target do
      nil -> socket
      g -> assign(socket, selected_symbol_id: g.symbol_id, selected_glyph_id: g.id)
    end
  end

  # Moves through the symbol key (most frequent first), skipping ignored ones.
  defp move_in_key(socket, step) do
    ids = for %{symbol: s} <- socket.assigns.key, !s.ignored, do: s.id

    case ids do
      [] ->
        socket

      ids ->
        index = Enum.find_index(ids, &(&1 == socket.assigns.selected_symbol_id))

        next =
          case index do
            nil -> if step > 0, do: 0, else: -1
            i -> rem(i + step + length(ids), length(ids))
          end

        assign(socket, selected_symbol_id: Enum.at(ids, next), selected_glyph_id: nil)
    end
  end
end
