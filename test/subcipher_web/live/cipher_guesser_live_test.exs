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

  # Clicks "Decode with this" on a guess: the cipher opens, to decode the text.
  defp use_guess(view, conn, selector) do
    view |> element(selector) |> render_click() |> follow_redirect(conn)
  end

  defp save(view, conn, title) do
    view
    |> form("#save-puzzle-form", puzzle: %{title: title})
    |> render_submit()
    |> follow_redirect(conn)
  end

  defp guess(view, text) do
    view |> form("#guess-form", guess: %{text: text}) |> render_submit()
    render_async(view, 60_000)
  end

  describe "logged in" do
    setup :register_and_log_in_user

    test "guesses the cipher, opens it with its settings, and saves a puzzle", %{
      conn: conn,
      scope: scope
    } do
      {:ok, view, _} = live(conn, ~p"/")
      assert has_element?(view, "#cipher-guesser")

      text = Caesar.encode(@plain, %{shift: 7})
      guess(view, text)

      assert has_element?(view, "#guess-list li:first-child#guess-caesar")
      refute has_element?(view, "#guess-no-match")

      {:ok, cipher, html} = use_guess(view, conn, "#guess-use-caesar")
      assert html =~ "Guessed settings applied"
      assert has_element?(cipher, "#mode-decode[aria-selected=true]")
      assert has_element?(cipher, "#algorithm-text", text)
      assert has_element?(cipher, "#stage-text-1", ~r/meet me at the old mill/i)

      {:ok, _show, _html} = save(cipher, conn, "Guessed")

      [%{puzzle: puzzle}] = Ciphers.list_puzzles(scope)
      assert puzzle.input_text == text
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

    test "the solvers find a shuffled alphabet, and its settings open the cipher", %{
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

      {:ok, cipher, _html} = use_guess(view, conn, "#guess-use-mixed_alphabet")
      assert has_element?(cipher, "#stage-text-1", ~r/beginning there was nothing/i)

      {:ok, _show, _html} = save(cipher, conn, "Solved")

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
    test "only the quick pass: the hint opens its cipher, and an invitation to log in", %{
      conn: conn
    } do
      {:ok, view, _} = live(conn, ~p"/")
      guess(view, MixedAlphabet.encode(@long_plain, %{mapping: @shuffled}))

      assert has_element?(view, "#guess-no-match")
      assert has_element?(view, "#guess-hint")
      assert has_element?(view, "#guess-deep-login")
      refute has_element?(view, "#guess-deep-pending")

      assert {:error, {:live_redirect, %{to: "/ciphers/mixed_alphabet?" <> _}}} =
               view |> element("#guess-hint-use") |> render_click()
    end

    test "can guess and decode, but must log in to save", %{conn: conn} do
      {:ok, view, _} = live(conn, ~p"/")

      guess(view, Caesar.encode(@plain, %{shift: 3}))
      assert has_element?(view, "#guess-caesar")

      {:ok, cipher, _html} = use_guess(view, conn, "#guess-use-caesar")
      assert has_element?(cipher, "#stage-text-1", ~r/meet me at the old mill/i)
      assert has_element?(cipher, "#save-draft-login")
      refute has_element?(cipher, "#save-puzzle-form")
    end
  end
end
