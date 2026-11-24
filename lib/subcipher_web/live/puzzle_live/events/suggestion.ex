defmodule SubcipherWeb.PuzzleLive.Events.Suggestion do
  @moduledoc """
  Events of the suggestions and solvers: showing suggestions (hidden until
  asked for), solving, and applying a suggestion or a solution.
  """
  import Phoenix.Component, only: [update: 3]
  import Subcipher.Util, only: [wrap: 2]

  alias Subcipher.{Ciphers, Steps}
  alias SubcipherWeb.PuzzleLive.Solver

  import SubcipherWeb.PuzzleLive.Assigns, only: [reload: 1]

  # Runs a solver in the background: for the symbols of the pictures, or
  # for the step shown.
  def handle_event("solve", %{"target" => "symbols"}, socket) do
    puzzle = socket.assigns.puzzle
    key = socket.assigns.symbols_solve_key
    socket |> Solver.run(key, fn -> Ciphers.solve_letters(puzzle) end) |> wrap(:noreply)
  end

  def handle_event("solve", %{"target" => _step_id}, socket) do
    case socket.assigns.current_entry do
      %{result: r, solve_key: key} ->
        socket
        |> Solver.run(key, fn -> Steps.solve(r.cipher, r.input, r.params) end)
        |> wrap(:noreply)

      _ ->
        wrap(socket, :noreply)
    end
  end

  def handle_event("apply_letters", %{"source" => source}, socket) do
    letters =
      case source do
        "frequency" ->
          case Ciphers.frequency_letters(socket.assigns.puzzle) do
            nil -> nil
            suggestion -> suggestion.letters
          end

        "solver" ->
          case socket.assigns.solutions[socket.assigns.symbols_solve_key] do
            {:ok, solution} -> solution.letters
            _ -> nil
          end
      end

    if letters do
      :ok = Ciphers.assign_letters(socket.assigns.puzzle, letters)
      socket |> reload() |> wrap(:noreply)
    else
      wrap(socket, :noreply)
    end
  end

  def handle_event("toggle_suggestions", %{"panel" => panel}, socket) do
    panel = to_string(panel)

    update(socket, :shown_suggestions, fn shown ->
      if MapSet.member?(shown, panel),
        do: MapSet.delete(shown, panel),
        else: MapSet.put(shown, panel)
    end)
    |> wrap(:noreply)
  end
end
