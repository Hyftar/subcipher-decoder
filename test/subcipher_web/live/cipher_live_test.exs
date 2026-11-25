defmodule SubcipherWeb.CipherLiveTest do
  use SubcipherWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias Subcipher.{Algorithms, Ciphers, Steps}

  describe "logged out" do
    test "a cipher can be tried: settings, steps, encode and decode", %{conn: conn} do
      {:ok, view, _} = live(conn, ~p"/ciphers/caesar")

      # It opens like a new algorithm, in its editor, to decode.
      assert has_element?(view, "#draft-label")
      assert has_element?(view, "#steps-editor")
      assert has_element?(view, "#mode-decode[aria-selected=true]")
      # Not saved: nothing to rename, share or delete.
      refute has_element?(view, "#title-form")
      refute has_element?(view, "#visibility")
      refute has_element?(view, "#delete-algorithm")

      view |> form("#editor-step-form-0", step: %{shift: "7"}) |> render_change()
      view |> form("#text-form", %{text: "Olssv"}) |> render_change()
      assert has_element?(view, "#stage-text-1", "Hello")

      # More steps, edited in place.
      view |> element("#editor-add-reverse") |> render_click()
      assert has_element?(view, "#editor-step-1")
      assert has_element?(view, "#stage-text-2", "olleH")

      view |> element("#mode-encode") |> render_click()
      assert_patch(view, ~p"/ciphers/caesar?mode=encode")
      view |> form("#text-form", %{text: "Hello"}) |> render_change()
      assert has_element?(view, "#stage-text-2", "vsslO")

      # Saving needs an account.
      assert has_element?(view, "#save-draft-login")
      refute has_element?(view, "#save-puzzle-form")
      assert has_element?(view, "#jump-to-save", "Log in to save")
    end

    test "saving or changing what only a saved algorithm has does nothing", %{conn: conn} do
      {:ok, view, _} = live(conn, ~p"/ciphers/caesar")

      assert {:error, {:live_redirect, %{to: "/users/log-in"}}} =
               render_hook(view, "save_puzzle", %{puzzle: %{title: "Mine"}})

      {:ok, view, _} = live(conn, ~p"/ciphers/caesar")
      render_hook(view, "delete", %{})
      render_hook(view, "toggle_public", %{})
      assert has_element?(view, "#draft-label")
    end

    test "?text= and ?params= prefill it; invalid settings are ignored", %{conn: conn} do
      {:ok, view, _} = live(conn, ~p"/ciphers/caesar?#{%{text: "Olssv", params: %{shift: 7}}}")
      assert has_element?(view, "#stage-text-1", "Hello")

      {:ok, view, _} = live(conn, ~p"/ciphers/caesar?#{%{text: "Khoor", params: %{shift: "x"}}}")
      assert has_element?(view, "#stage-text-1", "Hello")

      {:ok, view, _} = live(conn, "/ciphers/caesar?params=oops&text[a]=b")
      assert has_element?(view, "#steps-editor")
    end

    test "symbol substitution needs an account (pictures are uploaded)", %{conn: conn} do
      assert {:error, {:live_redirect, %{to: "/users/log-in", flash: %{"error" => _}}}} =
               live(conn, ~p"/ciphers/symbol_substitution")

      {:ok, view, _} = live(conn, ~p"/")

      assert {:error, {:live_redirect, %{to: "/users/log-in"}}} =
               view |> element("#new-cipher-symbol_substitution") |> render_click()

      assert {:error, {:live_redirect, %{to: "/users/log-in"}}} =
               live(conn, ~p"/?cipher=symbol_substitution")
    end

    test "an unknown cipher sends back to the home page", %{conn: conn} do
      assert {:error, {:live_redirect, %{to: "/", flash: %{"error" => message}}}} =
               live(conn, ~p"/ciphers/enigma")

      assert message =~ "doesn't exist"
    end
  end

  describe "logged in" do
    setup :register_and_log_in_user

    test "saves the steps as a puzzle decoding the cipher text", %{conn: conn, scope: scope} do
      {:ok, view, _} = live(conn, ~p"/ciphers/caesar")
      assert has_element?(view, "#jump-to-save", "Save as puzzle")
      assert has_element?(view, "#save-puzzle[disabled]")

      view |> form("#editor-step-form-0", step: %{shift: "7"}) |> render_change()
      view |> element("#editor-add-reverse") |> render_click()
      view |> form("#text-form", %{text: "Olssv dvysk"}) |> render_change()
      refute has_element?(view, "#save-puzzle[disabled]")

      {:ok, _puzzle_view, html} =
        view
        |> form("#save-puzzle-form", puzzle: %{title: "Two steps"})
        |> render_submit()
        |> follow_redirect(conn)

      assert html =~ "Puzzle saved"
      [%{puzzle: puzzle}] = Ciphers.list_puzzles(scope)
      assert %{title: "Two steps", input_kind: "text", input_text: "Olssv dvysk"} = puzzle
      assert [%{type: "caesar"} = caesar, %{type: "reverse"}] = Steps.list_steps(puzzle)
      assert Steps.params(caesar).shift == 7

      assert List.last(Steps.run(puzzle.input_text, Steps.list_steps(puzzle))).output ==
               "dlrow olleH"
    end

    test "encoding saves the encoded message", %{conn: conn, scope: scope} do
      {:ok, view, _} = live(conn, ~p"/ciphers/caesar?mode=encode")
      view |> form("#text-form", %{text: "Hello"}) |> render_change()

      view
      |> form("#save-puzzle-form", puzzle: %{title: "Encoded"})
      |> render_submit()

      [%{puzzle: puzzle}] = Ciphers.list_puzzles(scope)
      assert puzzle.input_text == "Khoor"
    end

    test "a title is required", %{conn: conn, scope: scope} do
      {:ok, view, _} = live(conn, ~p"/ciphers/caesar?#{%{text: "Khoor"}}")

      assert view
             |> form("#save-puzzle-form", puzzle: %{title: " "})
             |> render_submit() =~ "can&#39;t be blank"

      assert Ciphers.list_puzzles(scope) == []
      assert Algorithms.list_algorithms(scope) == []
    end

    test "symbol substitution opens the new puzzle page", %{conn: conn} do
      assert {:error, {:live_redirect, %{to: "/?cipher=symbol_substitution"}}} =
               live(conn, ~p"/ciphers/symbol_substitution")
    end
  end
end
