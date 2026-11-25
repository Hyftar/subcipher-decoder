defmodule SubcipherWeb.AlgorithmLive.Events.Save do
  @moduledoc """
  Saving a draft (an opened cipher) as a puzzle of the logged-in user: its
  steps, decoding the cipher text of the current mode (see `cipher_text/1`).
  """
  use SubcipherWeb, :verified_routes

  import Phoenix.Component, only: [assign: 2, to_form: 2]
  import Phoenix.LiveView, only: [put_flash: 3, push_navigate: 2]
  import Subcipher.Util, only: [wrap: 2]

  alias Subcipher.Algorithms

  @doc """
  The cipher text the puzzle decodes: the one typed to decode, or the
  encoded message.
  """
  def cipher_text(%{mode: "decode", texts: texts}), do: texts["decode"]
  def cipher_text(%{mode: "encode", trace: trace}), do: List.last(trace).value

  def handle_event(_event, _params, %{assigns: %{current_scope: nil}} = socket) do
    socket
    |> put_flash(:error, "Log in to save puzzles.")
    |> push_navigate(to: ~p"/users/log-in")
    |> wrap(:noreply)
  end

  def handle_event("validate_save", %{"puzzle" => params}, socket) do
    socket
    |> assign(save_form: to_form(%{"title" => params["title"] || ""}, as: :puzzle))
    |> wrap(:noreply)
  end

  def handle_event("save_puzzle", %{"puzzle" => params}, socket) do
    attrs = %{"title" => params["title"] || "", "input_text" => cipher_text(socket.assigns)}

    case Algorithms.save_as_puzzle(socket.assigns.current_scope, socket.assigns.algorithm, attrs) do
      {:ok, puzzle} ->
        socket
        |> put_flash(:info, "Puzzle saved.")
        |> push_navigate(to: ~p"/puzzles/#{puzzle}")
        |> wrap(:noreply)

      {:error, %Ecto.Changeset{} = changeset} ->
        socket
        |> assign(save_form: to_form(%{changeset | action: :insert}, as: :puzzle))
        |> wrap(:noreply)

      {:error, _} ->
        socket
        |> put_flash(:error, "Could not save the puzzle.")
        |> wrap(:noreply)
    end
  end
end
