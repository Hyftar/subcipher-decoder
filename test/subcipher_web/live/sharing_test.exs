defmodule SubcipherWeb.SharingTest do
  use SubcipherWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Subcipher.CipherFixtures
  import Subcipher.AccountsFixtures

  alias Subcipher.{Algorithms, Ciphers, Steps}

  defp text_algorithm(scope) do
    {:ok, algorithm} = Algorithms.create_algorithm(scope, "caesar", "Shift")
    {:ok, algorithm} = Algorithms.update_step_params(algorithm, 0, %{"shift" => "3"})
    algorithm
  end

  describe "logged out" do
    test "the home page asks to sign up, and lists what is public", %{conn: conn} do
      owner = user_scope_fixture()
      private = puzzle_fixture(owner)
      {:ok, public} = Ciphers.set_public(puzzle_fixture(owner), true)
      {:ok, algorithm} = Algorithms.set_public(text_algorithm(owner), true)

      {:ok, view, _} = live(conn, ~p"/")
      assert has_element?(view, "#sign-up-prompt")
      # Ciphers can be tried without an account, except from pictures.
      assert has_element?(view, "#choose-cipher")
      assert has_element?(view, "#new-cipher-symbol_substitution-locked")
      refute has_element?(view, "#new-cipher-caesar-locked")
      assert has_element?(view, "#public-puzzle-#{public.id}")
      refute has_element?(view, "#public-puzzle-#{private.id}")
      assert has_element?(view, "#public-algorithm-#{algorithm.id}")
      refute has_element?(view, "#puzzles")
    end

    test "private puzzles and algorithms can't be opened", %{conn: conn} do
      owner = user_scope_fixture()
      puzzle = puzzle_fixture(owner)
      algorithm = text_algorithm(owner)

      assert {:error, {:live_redirect, %{to: "/", flash: %{"error" => message}}}} =
               live(conn, ~p"/puzzles/#{puzzle}")

      assert message =~ "private"
      assert {:error, {:live_redirect, %{to: "/"}}} = live(conn, ~p"/algorithms/#{algorithm}")
    end
  end

  describe "logged in" do
    setup :register_and_log_in_user

    test "only the owner's puzzles are listed; others' stay private", %{conn: conn, scope: scope} do
      mine = puzzle_fixture(scope)
      theirs = puzzle_fixture(user_scope_fixture())

      {:ok, view, _} = live(conn, ~p"/")
      assert has_element?(view, "#puzzle-#{mine.id}")
      refute has_element?(view, "#puzzle-#{theirs.id}")
      refute has_element?(view, "#public-puzzle-#{theirs.id}")
      assert {:error, {:live_redirect, %{to: "/"}}} = live(conn, ~p"/puzzles/#{theirs}")
    end

    test "the owner makes a puzzle public, then private again", %{conn: conn, scope: scope} do
      puzzle = puzzle_fixture(scope)
      {:ok, view, _} = live(conn, ~p"/puzzles/#{puzzle}")

      assert has_element?(view, "#visibility[aria-pressed=false]")
      refute has_element?(view, "#read-only")
      view |> element("#visibility") |> render_click()
      assert has_element?(view, "#visibility[aria-pressed=true]")
      assert Ciphers.get_puzzle!(puzzle.id).public

      view |> element("#visibility") |> render_click()
      refute Ciphers.get_puzzle!(puzzle.id).public
    end

    test "someone else's public puzzle is read-only", %{conn: conn} do
      {:ok, puzzle} = Ciphers.set_public(puzzle_fixture(user_scope_fixture()), true)
      {:ok, view, _} = live(conn, ~p"/puzzles/#{puzzle}")

      assert has_element?(view, "#read-only")
      refute has_element?(view, "#title-form")
      refute has_element?(view, "#visibility")
      refute has_element?(view, "#make-algorithm")

      # Only the cipher text, output, symbol key and pictures: no edit control.
      assert has_element?(view, "#cipher-text")
      assert has_element?(view, "#plaintext")
      assert has_element?(view, "#symbol-key")
      assert has_element?(view, "#pictures")
      refute has_element?(view, "#add-picture")
      refute has_element?(view, "#suggestions-symbols")
      refute has_element?(view, "#keyboard-help")
      refute has_element?(view, "#reset-letters")
      refute has_element?(view, "#regroup-form")
      refute has_element?(view, "#symbol-key form")
      refute has_element?(view, "#step-nav-new")

      # Selecting and moving around work; typing a letter changes nothing.
      [first | _] = puzzle.glyphs
      view |> element("#glyph-#{first.id}") |> render_click()
      assert has_element?(view, "#symbol-#{first.symbol_id}.bg-primary\\/10")
      refute has_element?(view, "#selection-bar")
      refute has_element?(view, "#glyphs-button")
      view |> element("#puzzle") |> render_hook("key", %{"key" => "t"})
      view |> element("#puzzle") |> render_hook("key", %{"key" => "ArrowRight"})
      assert Enum.all?(Ciphers.get_puzzle!(puzzle.id).symbols, &is_nil(&1.letter))

      assert render_hook(view, "toggle_public", %{}) =~ "read-only"
      assert Ciphers.get_puzzle!(puzzle.id).public
    end

    test "someone else's public text puzzle shows its steps without edit controls", %{conn: conn} do
      owner = user_scope_fixture()

      {:ok, puzzle} =
        Ciphers.create_text_puzzle(owner, %{title: "Note", input_text: "Khoor"}, "caesar")

      {:ok, _} = Steps.update_params(hd(puzzle.steps), %{"shift" => "3"})
      {:ok, puzzle} = Ciphers.set_public(Ciphers.get_puzzle!(puzzle.id), true)
      [step] = puzzle.steps

      {:ok, view, _} = live(conn, ~p"/puzzles/#{puzzle}")

      assert view |> element("#step-input-#{step.id}") |> render() =~ "Khoor"
      assert view |> element("#step-output-#{step.id}") |> render() =~ "Hello"
      refute has_element?(view, "#input-form")
      refute has_element?(view, "#step-type-form-#{step.id}")
      refute has_element?(view, "#step-form-#{step.id}")
      refute has_element?(view, "#move-step-up-#{step.id}")
      refute has_element?(view, "#delete-step-#{step.id}")
      refute has_element?(view, "#suggestions-#{step.id}")
      refute has_element?(view, "#step-nav-new")

      # The "add a step" view isn't reachable either.
      {:ok, view, _} = live(conn, ~p"/puzzles/#{puzzle}?step=new")
      refute has_element?(view, "#add-step")
      assert has_element?(view, "#step-#{step.id}")
    end

    test "someone else's public algorithm can be used, not edited", %{conn: conn} do
      {:ok, algorithm} = Algorithms.set_public(text_algorithm(user_scope_fixture()), true)
      {:ok, view, _} = live(conn, ~p"/algorithms/#{algorithm}?edit=true")

      refute has_element?(view, "#steps-editor")
      refute has_element?(view, "#edit-algorithm")
      refute has_element?(view, "#delete-algorithm")
      refute has_element?(view, "#visibility")

      view |> form("#text-form", %{text: "Hello"}) |> render_change()
      assert view |> element("#stage-text-1") |> render() =~ "Khoor"

      render_hook(view, "add_step", %{"type" => "atbash"})
      render_hook(view, "delete", %{})
      assert [_] = Algorithms.get_algorithm!(algorithm.id).steps
    end

    test "a puzzle made into an algorithm gives it to the user", %{conn: conn, scope: scope} do
      {:ok, puzzle} =
        Ciphers.create_text_puzzle(scope, %{title: "Note", input_text: "x"}, "caesar")

      {:ok, _} = Steps.update_params(hd(puzzle.steps), %{"shift" => "1"})
      {:ok, view, _} = live(conn, ~p"/puzzles/#{puzzle}")

      {:error, {:live_redirect, %{to: "/algorithms/" <> _}}} =
        view |> element("#make-algorithm") |> render_click()

      assert [%{user_id: user_id, public: false}] = Algorithms.list_algorithms(scope)
      assert user_id == scope.user.id
    end
  end
end
