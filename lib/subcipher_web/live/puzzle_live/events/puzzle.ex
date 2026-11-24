defmodule SubcipherWeb.PuzzleLive.Events.Puzzle do
  @moduledoc "Events of the puzzle itself: visibility, title, making an algorithm."
  use SubcipherWeb, :verified_routes

  import Phoenix.Component, only: [assign: 2, to_form: 1]
  import Subcipher.Util, only: [wrap: 2]
  import Phoenix.LiveView, only: [put_flash: 3, push_navigate: 2]

  alias Subcipher.Ciphers

  import SubcipherWeb.PuzzleLive.Assigns, only: [reload: 1]

  def handle_event("toggle_public", _params, socket) do
    {:ok, puzzle} = Ciphers.set_public(socket.assigns.puzzle, !socket.assigns.puzzle.public)

    socket
    |> assign(puzzle: %{socket.assigns.puzzle | public: puzzle.public})
    |> put_flash(
      :info,
      if(puzzle.public,
        do: "Public: everyone can see it, read-only.",
        else: "Private: only you can see it."
      )
    )
    |> wrap(:noreply)
  end

  def handle_event("make_algorithm", _params, socket) do
    case Subcipher.Algorithms.create_from_puzzle(
           socket.assigns.current_scope,
           socket.assigns.puzzle
         ) do
      {:ok, algorithm} ->
        socket
        |> put_flash(:info, "Algorithm created: encode or decode any text with these steps.")
        |> push_navigate(to: ~p"/algorithms/#{algorithm}")
        |> wrap(:noreply)

      {:error, problems} ->
        put_flash(
          socket,
          :error,
          "This puzzle can't become an algorithm. " <> Enum.join(problems, " ")
        )
        |> wrap(:noreply)
    end
  end

  def handle_event("rename_blur", %{"value" => title}, socket) do
    if title == socket.assigns.puzzle.title,
      do: wrap(socket, :noreply),
      else: handle_event("rename", %{"puzzle" => %{"title" => title}}, socket)
  end

  def handle_event("rename", %{"puzzle" => params}, socket) do
    case Ciphers.update_title(socket.assigns.puzzle, params) do
      {:ok, puzzle} ->
        socket
        |> assign(page_title: puzzle.title)
        |> reload()
        |> wrap(:noreply)

      {:error, changeset} ->
        socket |> assign(title_form: to_form(changeset)) |> wrap(:noreply)
    end
  end
end
