defmodule SubcipherWeb.AlgorithmLive.Events.Image do
  @moduledoc "Events of the symbol image's options: style, alignment and colours."
  import Phoenix.Component, only: [assign: 2, update: 3]
  import Subcipher.Util, only: [wrap: 2]

  # The colour inputs: only the one changed (`_target`) is taken, so the
  # other stays "auto" (detected).
  def handle_event("image_options", %{"_target" => [field]} = params, socket)
      when field in ~w(background ink) do
    case valid_colour(params[field]) do
      nil -> wrap(socket, :noreply)
      colour -> socket |> update_image(String.to_existing_atom(field), colour) |> wrap(:noreply)
    end
  end

  def handle_event("image_options", _params, socket), do: wrap(socket, :noreply)

  def handle_event("image_align", %{"align" => align}, socket)
      when align in ~w(left center right),
      do: socket |> update_image(:align, align) |> wrap(:noreply)

  def handle_event("image_style", %{"style" => style}, socket)
      when style in ~w(original mask),
      do: socket |> update_image(:style, style) |> wrap(:noreply)

  def handle_event("image_auto", %{"colour" => field}, socket)
      when field in ~w(background ink),
      do: socket |> update_image(String.to_existing_atom(field), "auto") |> wrap(:noreply)

  def handle_event("image_transparent", _params, socket) do
    socket
    |> update_image(:transparent, !socket.assigns.image.transparent)
    |> wrap(:noreply)
  end

  # The colours the .SymbolImage hook detected in the glyphs (the last
  # valid one is kept for each).
  def handle_event("detected_colours", colours, socket) do
    detected =
      Map.new(~w(background ink)a, fn key ->
        {key, valid_colour(colours[Atom.to_string(key)]) || socket.assigns.detected[key]}
      end)

    socket
    |> assign(detected: detected)
    |> wrap(:noreply)
  end

  defp update_image(socket, key, value), do: update(socket, :image, &Map.put(&1, key, value))

  defp valid_colour("#" <> hex = colour) when byte_size(hex) == 6 do
    if hex =~ ~r/^[0-9a-fA-F]{6}$/, do: String.downcase(colour)
  end

  defp valid_colour(_), do: nil
end
