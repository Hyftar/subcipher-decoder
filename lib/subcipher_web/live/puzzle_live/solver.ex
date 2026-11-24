defmodule SubcipherWeb.PuzzleLive.Solver do
  @moduledoc """
  The "Try to solve" cards of the puzzle page: solvers run in the background
  (one at a time), and their results are kept by target and input.
  """
  import Phoenix.Component, only: [assign: 2, update: 3]
  import Subcipher.Util, only: [wrap: 2]
  import Phoenix.LiveView, only: [start_async: 3]

  alias Phoenix.LiveView.JS
  alias Subcipher.Guesser.Limiter

  # The solver card of the picture step: its solution applies letters.
  def symbols_solver_state(assigns) do
    case solver_state(assigns, assigns.symbols_solve_key) do
      {:ok, solution} ->
        {:ok, Map.put(solution, :use, JS.push("apply_letters", value: %{source: "solver"}))}

      state ->
        state
    end
  end

  # The state of the "Try to solve" card for `key`.
  def solver_state(%{solving: key}, key), do: :running

  def solver_state(assigns, key) do
    case Map.get(assigns.solutions, key) do
      nil ->
        :idle

      {:ok, solution} ->
        Map.put(solution, :applied, solution_applied?(assigns, solution))
        |> wrap(:ok)

      error ->
        error
    end
  end

  # Whether a solution is what's currently set (letters or step settings).
  defp solution_applied?(%{symbols: symbols}, %{letters: letters}),
    do: Enum.all?(letters, fn {id, letter} -> match?(%{letter: ^letter}, symbols[id]) end)

  defp solution_applied?(%{current_entry: %{result: r}}, %{params: params}),
    do: Map.merge(r.params, params) == r.params

  defp solution_applied?(_, _), do: false

  @doc """
  Runs `fun` in the background as the solver of `key`, in a slot of
  `Subcipher.Guesser.Limiter` (solvers are CPU-heavy: when the server is
  busy, it says so instead) and for at most
  `config :subcipher, :guesser_deep_timeout` ms (default 30 s).
  """
  def run(socket, key, fun) do
    timeout = Application.get_env(:subcipher, :guesser_deep_timeout, 30_000)

    socket
    |> assign(solving: key)
    |> start_async(:solve, fn -> {key, limited(fun, timeout)} end)
  end

  defp limited(fun, timeout) do
    result =
      Limiter.run(fn ->
        task = Task.async(fun)
        Task.yield(task, timeout) || Task.shutdown(task, :brutal_kill)
      end)

    case result do
      {:ok, {:ok, solution}} ->
        solution

      {:ok, _timeout} ->
        {:error, "The solver took too long and was stopped. Try fixing a few letters first."}

      {:error, :busy} ->
        {:error, "The server is busy solving other puzzles: try again in a moment."}
    end
  end

  @doc "Keeps the result of the solver (`handle_async/3` of `:solve`)."
  def handle_async({:ok, {key, result}}, socket) do
    socket
    |> update(:solutions, &Map.put(&1, key, result))
    |> assign(solving: nil)
    |> wrap(:noreply)
  end

  def handle_async({:exit, _reason}, socket) do
    key = socket.assigns.solving

    socket
    |> update(:solutions, &Map.put(&1, key, {:error, "The solver stopped unexpectedly."}))
    |> assign(solving: nil)
    |> wrap(:noreply)
  end
end
