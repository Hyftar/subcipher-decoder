defmodule SubcipherWeb.PuzzleLive.Events.Glyph do
  @moduledoc """
  Events of the glyphs panel: the occurrence edited, how it is shown, the
  symbol's sample and the crop of each occurrence.
  """
  import Phoenix.Component, only: [assign: 2, update: 3]
  import Subcipher.Util, only: [wrap: 2]

  alias Subcipher.Ciphers

  import SubcipherWeb.PuzzleLive.Assigns, only: [find_glyph: 2, reload: 1]

  def handle_event("toggle_glyphs", _params, socket) do
    socket |> update(:show_glyphs, &(!&1)) |> wrap(:noreply)
  end

  # An occurrence picked in the glyphs panel: edited there, without moving
  # the selection in the text.
  def handle_event("edit_glyph", %{"id" => id}, socket) do
    case find_glyph(socket, id) do
      %{symbol_id: symbol_id} = glyph when symbol_id == socket.assigns.selected_symbol_id ->
        socket |> assign(edited_glyph_id: glyph.id) |> wrap(:noreply)

      _ ->
        wrap(socket, :noreply)
    end
  end

  def handle_event("glyph_view", %{"view" => view}, socket) when view in ~w(original mask) do
    socket |> assign(glyph_view: view) |> wrap(:noreply)
  end

  def handle_event("set_sample", %{"id" => id}, socket) do
    case find_glyph(socket, id) do
      nil ->
        wrap(socket, :noreply)

      glyph ->
        :ok = Ciphers.set_sample(glyph)
        socket |> reload() |> wrap(:noreply)
    end
  end

  def handle_event("trim_glyph", %{"id" => id} = params, socket) do
    with %{} = glyph <- find_glyph(socket, id),
         {:ok, _} <- Ciphers.trim_glyph(glyph, Map.take(params, ~w(x y w h))) do
      socket |> reload() |> wrap(:noreply)
    else
      _ -> wrap(socket, :noreply)
    end
  end

  def handle_event("reset_trim", %{"id" => id}, socket) do
    case find_glyph(socket, id) do
      nil ->
        wrap(socket, :noreply)

      glyph ->
        {:ok, _} = Ciphers.reset_glyph_box(glyph)
        socket |> reload() |> wrap(:noreply)
    end
  end
end
