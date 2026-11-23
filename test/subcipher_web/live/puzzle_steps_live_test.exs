defmodule SubcipherWeb.PuzzleStepsLiveTest do
  use SubcipherWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Subcipher.CipherFixtures

  alias Subcipher.{Ciphers, Steps}

  # Pictures puzzle whose step 1 deciphers to the pangram encrypted with a
  # Caesar shift of 3.
  defp shifted_pangram_puzzle do
    puzzle = puzzle_fixture()

    for {symbol_id, <<c>>} <- solution(puzzle) do
      symbol = Enum.find(puzzle.symbols, &(&1.id == symbol_id))
      {:ok, _} = Ciphers.assign_letter(symbol, <<?A + rem(c - ?A + 3, 26)>>)
    end

    puzzle
  end

  # Adds a step through the "+" of the step navigation; returns it.
  defp add_step(view, puzzle, type) do
    view |> element("#step-nav-new") |> render_click()
    assert has_element?(view, "#add-step")
    view |> element("#add-step-#{type}") |> render_click()
    puzzle |> Steps.list_steps() |> List.last()
  end

  defp output(view, step), do: view |> element("#step-output-#{step.id}") |> render()

  describe "step navigation (pictures puzzle)" do
    setup do
      %{puzzle: shifted_pangram_puzzle()}
    end

    test "step 1 is the symbol substitution of the pictures", %{conn: conn, puzzle: puzzle} do
      {:ok, view, _} = live(conn, ~p"/puzzles/#{puzzle}")

      assert has_element?(view, "#step-nav-1[aria-current=step]", "1")
      assert has_element?(view, "#step-nav", "Symbol substitution")
      assert has_element?(view, "#step-nav-new")
      assert has_element?(view, "#cipher-text")
      assert view |> element("#plaintext") |> render() =~ "WKH TXLFN EURZQ IRA"
      refute has_element?(view, "#final-output")
    end

    test "the + adds a step, which is then shown", %{conn: conn, puzzle: puzzle} do
      {:ok, view, _} = live(conn, ~p"/puzzles/#{puzzle}")
      step = add_step(view, puzzle, "caesar")

      assert_patch(view, ~p"/puzzles/#{puzzle}?step=2")
      assert has_element?(view, "#step-nav-2[aria-current=step]", "2")
      assert has_element?(view, "#step-#{step.id}")
      refute has_element?(view, "#cipher-text")

      # Its input is step 1's output, decoded with the default shift of 3.
      assert view |> element("#step-input-#{step.id}") |> render() =~ "WKH TXLFN"
      assert output(view, step) =~ "THE QUICK BROWN FOX"

      # Back to step 1: the final output is shown there.
      view |> element("#step-nav-1") |> render_click()
      assert has_element?(view, "#cipher-text")
      assert view |> element("#final-output") |> render() =~ "THE QUICK BROWN FOX"
    end

    test "?step=N opens a step directly; unknown steps fall back", %{conn: conn, puzzle: puzzle} do
      {:ok, step} = Steps.add_step(puzzle, "caesar")

      {:ok, view, _} = live(conn, ~p"/puzzles/#{puzzle}?step=2")
      assert has_element?(view, "#step-#{step.id}")

      {:ok, view, _} = live(conn, ~p"/puzzles/#{puzzle}?step=9")
      assert has_element?(view, "#step-nav-2[aria-current=step]")

      {:ok, view, _} = live(conn, ~p"/puzzles/#{puzzle}?step=new")
      assert has_element?(view, "#add-step")
    end

    test "settings decode live; invalid ones keep the last valid", %{conn: conn, puzzle: puzzle} do
      {:ok, view, _} = live(conn, ~p"/puzzles/#{puzzle}")
      step = add_step(view, puzzle, "caesar")

      view |> form("#step-form-#{step.id}", step: %{shift: "4"}) |> render_change()
      assert output(view, step) =~ "SGD PTHBJ"

      view |> form("#step-form-#{step.id}", step: %{shift: "40"}) |> render_change()
      assert has_element?(view, "#step-form-#{step.id}", "must be less than or equal to 25")
      assert output(view, step) =~ "SGD PTHBJ"
    end

    test "Caesar key suggestions rank the right shift first", %{conn: conn, puzzle: puzzle} do
      {:ok, view, _} = live(conn, ~p"/puzzles/#{puzzle}")
      step = add_step(view, puzzle, "caesar")
      view |> form("#step-form-#{step.id}", step: %{shift: "0"}) |> render_change()

      view |> element("#toggle-candidates-#{step.id}") |> render_click()
      assert has_element?(view, "#candidate-#{step.id}-0", "Shift 3")

      view |> element("#candidate-#{step.id}-0") |> render_click()
      assert output(view, step) =~ "THE QUICK BROWN FOX"
      assert hd(Steps.list_steps(puzzle)).params == %{"shift" => 3}
    end

    test "steps chain, and a step's cipher can be changed", %{conn: conn, puzzle: puzzle} do
      {:ok, view, _} = live(conn, ~p"/puzzles/#{puzzle}")
      _caesar = add_step(view, puzzle, "caesar")
      letters = add_step(view, puzzle, "letter_substitution")
      assert_patch(view, ~p"/puzzles/#{puzzle}?step=3")

      assert view |> element("#step-input-#{letters.id}") |> render() =~ "THE QUICK"
      assert output(view, letters) =~ "··· ····· ····· ···"

      view
      |> form("#step-form-#{letters.id}", step: %{mapping: %{"T" => "x", "H" => "y", "E" => "z"}})
      |> render_change()

      assert output(view, letters) =~ "XYZ ····· ····· ···"

      # Same step, another cipher: settings are reset.
      view
      |> form("#step-type-form-#{letters.id}", %{type: "keyword_substitution"})
      |> render_change()

      assert has_element?(view, "#step-nav-3", "3")
      assert has_element?(view, "#step-nav", "Keyword substitution")
      assert hd(tl(Steps.list_steps(puzzle))).params == %{"keyword" => ""}
      assert output(view, letters) =~ "THE QUICK"
    end

    test "steps can be reordered and removed", %{conn: conn, puzzle: puzzle} do
      {:ok, view, _} = live(conn, ~p"/puzzles/#{puzzle}")
      caesar = add_step(view, puzzle, "caesar")
      letters = add_step(view, puzzle, "letter_substitution")

      assert has_element?(view, "#move-step-down-#{letters.id}[disabled]")
      view |> element("#move-step-up-#{letters.id}") |> render_click()
      assert_patch(view, ~p"/puzzles/#{puzzle}?step=2")
      assert Enum.map(Steps.list_steps(puzzle), & &1.id) == [letters.id, caesar.id]
      # Step 2 can't move before the pictures.
      assert has_element?(view, "#move-step-up-#{letters.id}[disabled]")

      view |> element("#delete-step-#{letters.id}") |> render_click()
      assert_patch(view, ~p"/puzzles/#{puzzle}?step=1")
      assert Enum.map(Steps.list_steps(puzzle), & &1.id) == [caesar.id]
      refute has_element?(view, "#step-nav-3")
    end
  end

  describe "text puzzles" do
    test "are created from text, with any cipher as step 1", %{conn: conn} do
      {:ok, view, _} = live(conn, ~p"/")
      view |> element("#input-kind-text") |> render_click()

      {:ok, view, _} =
        view
        |> form("#new-text-puzzle-form",
          puzzle: %{title: "Note", input_text: "Wkh txlfn eurzq ira"},
          first_step: "caesar"
        )
        |> render_submit()
        |> follow_redirect(conn)

      [%{puzzle: puzzle}] = Ciphers.list_puzzles()
      [step] = Steps.list_steps(puzzle)
      assert step.type == "caesar"

      assert has_element?(view, "#step-nav-1[aria-current=step]")
      refute has_element?(view, "#progress")
      assert view |> element("#input-text") |> render() =~ "Wkh txlfn eurzq ira"
      assert output(view, step) =~ "The quick brown fox"
    end

    test "require a text", %{conn: conn} do
      {:ok, view, _} = live(conn, ~p"/")
      view |> element("#input-kind-text") |> render_click()

      view
      |> form("#new-text-puzzle-form",
        puzzle: %{title: "Empty", input_text: ""},
        first_step: "caesar"
      )
      |> render_submit()

      assert has_element?(view, "#new-text-puzzle-form", "can't be blank")
      assert Ciphers.list_puzzles() == []
    end

    test "symbol substitution on text and editing the input", %{conn: conn} do
      {:ok, puzzle} =
        Ciphers.create_text_puzzle(%{title: "Stars", input_text: "☀♪Θ ☀"}, "symbol_substitution")

      [step] = puzzle.steps
      {:ok, view, _} = live(conn, ~p"/puzzles/#{puzzle}")

      # One input per distinct symbol, most frequent first.
      assert has_element?(view, "#step-#{step.id}-symbol-0[aria-label='Letter for ☀']")
      assert output(view, step) =~ "··· ·"

      view
      |> form("#step-form-#{step.id}", step: %{mapping: %{"u9728" => "t", "u9834" => "o"}})
      |> render_change()

      assert output(view, step) =~ "TO· T"

      view |> form("#input-form", puzzle: %{input_text: "Θ☀"}) |> render_change()
      assert Ciphers.get_puzzle!(puzzle.id).input_text == "Θ☀"
      assert output(view, step) =~ "·T"

      # A text puzzle keeps at least one step.
      assert has_element?(view, "#delete-step-#{step.id}[disabled]")
    end
  end
end
