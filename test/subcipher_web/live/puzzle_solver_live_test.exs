defmodule SubcipherWeb.PuzzleSolverLiveTest do
  use SubcipherWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Subcipher.CipherFixtures

  # Puzzles and algorithms are created for the logged-in user (`scope`).
  setup :register_and_log_in_user

  alias Subcipher.Ciphers

  describe "picture step suggestions" do
    test "frequency match fills the symbols without a letter", %{conn: conn, scope: scope} do
      puzzle = puzzle_fixture(scope)
      {:ok, view, _} = live(conn, ~p"/puzzles/#{puzzle}")

      # Hidden until asked for: they can spoil the puzzle.
      assert has_element?(view, "#suggestions-symbols")
      refute has_element?(view, "#suggestion-symbols-0")

      view |> element("#toggle-suggestions-symbols") |> render_click()
      assert has_element?(view, "#suggestion-symbols-0", "Frequency match")
      assert view |> element("#progress") |> render() =~ "0 / 26"

      view |> element("#apply-suggestion-symbols-0") |> render_click()
      assert view |> element("#progress") |> render() =~ "26 / 26"
      # Nothing left to fill.
      refute has_element?(view, "#suggestion-symbols-0")
    end

    test "Try to solve runs in the background, then can be applied", %{conn: conn, scope: scope} do
      puzzle = puzzle_fixture(scope)
      {:ok, view, _} = live(conn, ~p"/puzzles/#{puzzle}")

      view |> element("#solve-symbols") |> render_click()
      assert has_element?(view, "#solver-symbols", "Solving")
      refute has_element?(view, "#solve-symbols")

      render_async(view, 30_000)
      assert has_element?(view, "#solution-symbols", "Solver")
      assert has_element?(view, "#solution-symbols", "words are English words")
      assert has_element?(view, "#solve-symbols", "Solve again")

      view |> element("#apply-solution-symbols") |> render_click()
      assert view |> element("#progress") |> render() =~ "26 / 26"
      assert has_element?(view, "#solution-symbols", "Applied")
    end
  end

  test "text steps with a solver get Try to solve", %{conn: conn, scope: scope} do
    {:ok, puzzle} =
      Ciphers.create_text_puzzle(
        scope,
        %{title: "Stars", input_text: "☀♪Θ ♠Φ☎Θ ☀♪Θ ★♣♥ ♦☂✈ ☀♪Θ ⚓☯⚑ ✿☘⌘"},
        "symbol_substitution"
      )

    [step] = puzzle.steps
    {:ok, view, _} = live(conn, ~p"/puzzles/#{puzzle}")

    view |> element("#solve-#{step.id}") |> render_click()
    render_async(view, 30_000)
    assert has_element?(view, "#solution-#{step.id}", "Solver")

    view |> element("#apply-solution-#{step.id}") |> render_click()
    refute view |> element("#step-output-#{step.id}") |> render() =~ "·"
  end

  test "frequency_letters/1 keeps the letters already set" do
    puzzle = puzzle_fixture()
    tokens = Ciphers.symbol_tokens(puzzle)

    most_frequent =
      tokens
      |> Enum.reject(&(&1 == :gap))
      |> Enum.frequencies()
      |> Enum.max_by(&elem(&1, 1))
      |> elem(0)

    {:ok, _} = Ciphers.assign_letter(Enum.find(puzzle.symbols, &(&1.id == most_frequent)), "Q")
    suggestion = puzzle.id |> Ciphers.get_puzzle!() |> Ciphers.frequency_letters()

    refute Map.has_key?(suggestion.letters, most_frequent)
    refute "Q" in Map.values(suggestion.letters)
    assert suggestion.reason =~ "Your 1 letter(s) are kept."
  end
end
