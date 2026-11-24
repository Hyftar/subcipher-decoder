defmodule SubcipherWeb.CipherGuesserLiveTest do
  use SubcipherWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias Subcipher.{Ciphers, Steps}
  alias Subcipher.Steps.Ciphers.{Caesar, MixedAlphabet}

  @plain "Meet me at the old mill at midnight and bring the map with you"
  @long_plain "In the beginning there was nothing but darkness and the gods fought over the world"
  @shuffled Map.new(
              Enum.zip(Enum.map(?A..?Z, &<<&1>>), String.graphemes("QWERTYUIOPASDFGHJKLZXCVBNM"))
            )

  defp guess(view, text) do
    view |> form("#guess-form", guess: %{text: text}) |> render_submit()
    render_async(view, 60_000)
  end

  describe "logged in" do
    setup :register_and_log_in_user

    test "guesses the cipher and starts a puzzle with its settings", %{conn: conn, scope: scope} do
      {:ok, view, _} = live(conn, ~p"/")
      assert has_element?(view, "#cipher-guesser")

      text = Caesar.encode(@plain, %{shift: 7})
      guess(view, text)

      assert has_element?(view, "#guess-list li:first-child#guess-caesar")
      refute has_element?(view, "#guess-no-match")

      view |> element("#guess-use-caesar") |> render_click()
      assert_patch(view, ~p"/?cipher=caesar&input=text")
      assert has_element?(view, "#guess-choice")
      assert has_element?(view, "#new-text-puzzle-form textarea", text)

      {:ok, _show, _html} =
        view
        |> form("#new-text-puzzle-form", puzzle: %{title: "Guessed"})
        |> render_submit()
        |> follow_redirect(conn)

      [%{puzzle: puzzle}] = Ciphers.list_puzzles(scope)
      [step] = Steps.list_steps(puzzle)
      assert step.type == "caesar"
      assert Steps.params(step).shift == 7
    end

    test "solutions and keys are hidden until toggled, and hidden again on a new guess", %{
      conn: conn
    } do
      {:ok, view, _} = live(conn, ~p"/")
      guess(view, Caesar.encode(@plain, %{shift: 7}))

      refute has_element?(view, "#guess-preview-caesar")
      refute has_element?(view, "#guess-label-caesar")
      refute has_element?(view, "#guess-reason-caesar")
      refute render(view) =~ "Shift 7"
      assert has_element?(view, "#guess-reveal-caesar[aria-checked=false]")

      view |> element("#guess-reveal-caesar") |> render_click()
      assert has_element?(view, "#guess-preview-caesar", ~r/meet me at the old mill/i)
      assert has_element?(view, "#guess-label-caesar", "Shift 7")
      assert has_element?(view, "#guess-reason-caesar")
      assert has_element?(view, "#guess-reveal-caesar[aria-checked=true]")

      view |> element("#guess-reveal-caesar") |> render_click()
      refute has_element?(view, "#guess-preview-caesar")
      refute has_element?(view, "#guess-label-caesar")

      view |> element("#guess-reveal-caesar") |> render_click()
      guess(view, Caesar.encode(@plain, %{shift: 3}))
      refute has_element?(view, "#guess-preview-caesar")
    end

    test "the solvers find a shuffled alphabet, and its settings start the puzzle", %{
      conn: conn,
      scope: scope
    } do
      {:ok, view, _} = live(conn, ~p"/")
      text = MixedAlphabet.encode(@long_plain, %{mapping: @shuffled})

      guess(view, text)
      assert has_element?(view, "#guess-list li:first-child#guess-mixed_alphabet")
      assert has_element?(view, "#guess-solver-mixed_alphabet")
      refute has_element?(view, "#guess-deep-pending")
      refute has_element?(view, "#guess-no-match")

      view |> element("#guess-use-mixed_alphabet") |> render_click()
      assert_patch(view, ~p"/?cipher=mixed_alphabet&input=text")
      assert has_element?(view, "#guess-choice")

      {:ok, _show, _html} =
        view
        |> form("#new-text-puzzle-form", puzzle: %{title: "Solved"})
        |> render_submit()
        |> follow_redirect(conn)

      [%{puzzle: puzzle}] = Ciphers.list_puzzles(scope)
      [step] = Steps.list_steps(puzzle)
      assert MixedAlphabet.decode(text, Steps.params(step)) =~ ~r/beginning there was nothing/i
    end

    test "recognizes short Morse code", %{conn: conn} do
      {:ok, view, _} = live(conn, ~p"/")
      guess(view, "... --- ...")

      assert has_element?(view, "#guess-list li:first-child#guess-morse")
      assert has_element?(view, "#guess-recognized-morse")
      refute has_element?(view, "#guess-no-match")
    end

    test "says when the text is too short", %{conn: conn} do
      {:ok, view, _} = live(conn, ~p"/")
      guess(view, "abc")
      assert has_element?(view, "#guess-error")
    end
  end

  describe "logged out" do
    test "only the quick pass: the hint, and an invitation to log in", %{conn: conn} do
      {:ok, view, _} = live(conn, ~p"/")
      guess(view, MixedAlphabet.encode(@long_plain, %{mapping: @shuffled}))

      assert has_element?(view, "#guess-no-match")
      assert has_element?(view, "#guess-hint")
      assert has_element?(view, "#guess-deep-login")
      refute has_element?(view, "#guess-deep-pending")

      assert {:error, {:live_redirect, %{to: "/users/log-in"}}} =
               view |> element("#guess-hint-use") |> render_click()
    end

    test "can guess, but must log in to decode", %{conn: conn} do
      {:ok, view, _} = live(conn, ~p"/")

      guess(view, Caesar.encode(@plain, %{shift: 3}))
      assert has_element?(view, "#guess-caesar")

      assert {:error, {:live_redirect, %{to: "/users/log-in"}}} =
               view |> element("#guess-use-caesar") |> render_click()
    end
  end
end
