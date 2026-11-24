defmodule SubcipherWeb.PuzzleLive.Events.Picture do
  @moduledoc "Events of the pictures of a puzzle: panels, order, removal."
  import Phoenix.Component, only: [update: 3]
  import Subcipher.Util, only: [wrap: 2]
  import Phoenix.LiveView, only: [put_flash: 3]

  alias Subcipher.Ciphers

  import SubcipherWeb.PuzzleLive.Assigns, only: [load: 2]

  def handle_event("toggle_image", _params, socket) do
    socket |> update(:show_image, &(!&1)) |> wrap(:noreply)
  end

  def handle_event("toggle_add", _params, socket) do
    socket |> update(:show_add, &(!&1)) |> wrap(:noreply)
  end

  def handle_event("move_image", %{"id" => id, "direction" => direction}, socket)
      when direction in ~w(up down) do
    image = Enum.find(socket.assigns.puzzle.images, &(to_string(&1.id) == id))

    case image && Ciphers.move_image(image, String.to_existing_atom(direction)) do
      {:ok, puzzle} -> socket |> load(puzzle) |> wrap(:noreply)
      _ -> socket |> put_flash(:error, "Could not move the picture.") |> wrap(:noreply)
    end
  end

  def handle_event("delete_image", %{"id" => id}, socket) do
    image = Enum.find(socket.assigns.puzzle.images, &(to_string(&1.id) == id))

    case image && Ciphers.delete_image(image) do
      {:ok, puzzle} ->
        socket |> load(puzzle) |> put_flash(:info, "Picture removed.") |> wrap(:noreply)

      {:error, :last_image} ->
        socket |> put_flash(:error, "A cipher needs at least one picture.") |> wrap(:noreply)

      _ ->
        socket |> put_flash(:error, "Could not remove the picture.") |> wrap(:noreply)
    end
  end
end
