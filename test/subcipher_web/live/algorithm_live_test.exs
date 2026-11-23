defmodule SubcipherWeb.AlgorithmLiveTest do
  use SubcipherWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Subcipher.CipherFixtures

  # Puzzles and algorithms are created for the logged-in user (`scope`).
  setup :register_and_log_in_user

  alias Subcipher.{Algorithms, Ciphers, Steps}

  defp text_algorithm(scope) do
    {:ok, puzzle} =
      Ciphers.create_text_puzzle(scope, %{title: "Secret", input_text: "x"}, "caesar")

    {:ok, _} = Steps.update_params(hd(puzzle.steps), %{"shift" => "3"})
    {:ok, algorithm} = Algorithms.create_from_puzzle(scope, Ciphers.get_puzzle!(puzzle.id))
    algorithm
  end

  test "encode and decode, with the text after each step", %{conn: conn, scope: scope} do
    algorithm = text_algorithm(scope)
    {:ok, view, _} = live(conn, ~p"/algorithms/#{algorithm}")

    assert has_element?(view, "#algorithm-step-1", "Caesar cipher")
    assert has_element?(view, "#mode-encode[aria-selected=true]")
    # Nothing to copy yet.
    refute has_element?(view, "#stage-text-1-copy")

    view |> form("#text-form", %{text: "Hello"}) |> render_change()
    assert has_element?(view, "#stage-text-1-copy")
    assert view |> element("#stage-text-0") |> render() =~ "Hello"
    assert view |> element("#stage-text-1") |> render() =~ "Khoor"

    view |> element("#mode-decode") |> render_click()
    assert_patch(view, ~p"/algorithms/#{algorithm}?mode=decode")
    view |> form("#text-form", %{text: "Khoor"}) |> render_change()
    assert view |> element("#stage-text-1") |> render() =~ "Hello"

    # Each mode keeps its own text.
    view |> element("#mode-encode") |> render_click()
    assert view |> element("#algorithm-text") |> render() =~ "Hello"
  end

  test "a pictures algorithm draws symbols, and decodes clicked symbols", %{
    conn: conn,
    scope: scope
  } do
    puzzle = puzzle_fixture(scope)

    for {symbol_id, letter} <- solution(puzzle) do
      {:ok, _} = Ciphers.assign_letter(Enum.find(puzzle.symbols, &(&1.id == symbol_id)), letter)
    end

    {:ok, algorithm} = Algorithms.create_from_puzzle(scope, Ciphers.get_puzzle!(puzzle.id))
    {:ok, view, _} = live(conn, ~p"/algorithms/#{algorithm}")

    # No image (and no detected background) until there is something to draw.
    refute has_element?(view, "#symbol-image")
    assert has_element?(view, "#symbol-image-empty")

    view |> form("#text-form", %{text: "hi"}) |> render_change()
    assert %{"lines" => [[%{"t" => "glyph"}, %{"t" => "glyph"}]]} = image_spec(view)
    refute has_element?(view, "#symbol-image-empty")

    {:ok, view, _} = live(conn, ~p"/algorithms/#{algorithm}?mode=decode")
    refute has_element?(view, "#text-form")
    refute has_element?(view, "#symbol-image")
    h = Enum.find_index(algorithm.symbol_key, &(&1["letter"] == "H"))
    i = Enum.find_index(algorithm.symbol_key, &(&1["letter"] == "I"))

    # Each key shows the letter it stands for.
    assert has_element?(view, "#key-#{h}-letter", "H")

    view |> element("#key-#{h}") |> render_click()
    view |> element("#key-#{i}") |> render_click()
    assert view |> element("#stage-text-1") |> render() =~ "HI"

    # The cipher symbols are drawn like the encoded image, with its options.
    assert %{"lines" => [[%{"t" => "glyph"}, %{"t" => "glyph"}]]} = image_spec(view)
    view |> element("#align-left") |> render_click()
    assert image_spec(view)["align"] == "left"

    view |> element("#key-backspace") |> render_click()
    assert view |> element("#stage-text-1") |> render() =~ "H"
    refute view |> element("#stage-text-1") |> render() =~ "HI"
  end

  defp image_spec(view) do
    view
    |> element("#symbol-image")
    |> render()
    |> LazyHTML.from_fragment()
    |> LazyHTML.attribute("data-spec")
    |> hd()
    |> Jason.decode!()
  end

  test "the encoded image: lines, style, alignment and colours", %{conn: conn, scope: scope} do
    puzzle = puzzle_fixture(scope)

    for {symbol_id, letter} <- solution(puzzle) do
      {:ok, _} = Ciphers.assign_letter(Enum.find(puzzle.symbols, &(&1.id == symbol_id)), letter)
    end

    {:ok, algorithm} = Algorithms.create_from_puzzle(scope, Ciphers.get_puzzle!(puzzle.id))
    {:ok, view, _} = live(conn, ~p"/algorithms/#{algorithm}")
    view |> form("#text-form", %{text: "hi you\nok 1"}) |> render_change()

    spec = image_spec(view)
    assert spec["images"] == [hd(algorithm.images)["path"]]

    assert [
             [_, _, %{"t" => "space"}, _, _, _],
             [_, _, %{"t" => "space"}, %{"t" => "char", "c" => "1"}]
           ] =
             spec["lines"]

    assert %{"style" => "original", "align" => "center", "background" => "auto"} = spec

    view |> element("#align-right") |> render_click()
    assert image_spec(view)["align"] == "right"
    assert has_element?(view, "#align-right[aria-pressed=true]")

    # The hook reports the glyphs' colours; a background can be chosen instead.
    render_hook(view, "detected_colours", %{background: "#6b5a3c", ink: nil})
    assert has_element?(view, "#background-auto span[style*='#6b5a3c']")
    refute has_element?(view, "#ink-color")

    view
    |> form("#image-options")
    |> render_change(%{"_target" => ["background"], "background" => "#FFEEDD"})

    assert image_spec(view)["background"] == "#ffeedd"

    view |> element("#background-auto") |> render_click()
    assert image_spec(view)["background"] == "auto"

    # Two colours: the black and white pass, in a glyph colour, on a plain
    # or transparent background.
    view |> element("#style-mask") |> render_click()
    render_hook(view, "detected_colours", %{background: "#6b5a3c", ink: "#f0a0c0"})
    assert has_element?(view, "#ink-auto span[style*='#f0a0c0']")

    view
    |> form("#image-options")
    |> render_change(%{"_target" => ["ink"], "ink" => "#112233", "background" => "#6b5a3c"})

    assert %{"style" => "mask", "ink" => "#112233", "background" => "auto"} = image_spec(view)

    view |> element("#background-transparent") |> render_click()
    assert image_spec(view)["transparent"] == true
    assert has_element?(view, "#background-color[disabled]")

    view |> element("#ink-auto") |> render_click()
    assert image_spec(view)["ink"] == "auto"
  end

  test "space and new line keys of the symbol keyboard", %{conn: conn, scope: scope} do
    puzzle = puzzle_fixture(scope)

    for {symbol_id, letter} <- solution(puzzle) do
      {:ok, _} = Ciphers.assign_letter(Enum.find(puzzle.symbols, &(&1.id == symbol_id)), letter)
    end

    {:ok, algorithm} = Algorithms.create_from_puzzle(scope, Ciphers.get_puzzle!(puzzle.id))
    {:ok, view, _} = live(conn, ~p"/algorithms/#{algorithm}?mode=decode")
    a = Enum.find_index(algorithm.symbol_key, &(&1["letter"] == "A"))
    b = Enum.find_index(algorithm.symbol_key, &(&1["letter"] == "B"))

    view |> element("#key-#{a}") |> render_click()
    view |> element("#key-space") |> render_click()
    view |> element("#key-#{b}") |> render_click()
    view |> element("#key-newline") |> render_click()
    view |> element("#key-#{a}") |> render_click()

    assert view |> element("#stage-text-1") |> render() =~ "A B\nA"
  end

  test "made from the puzzle page, listed on the home page", %{conn: conn, scope: scope} do
    {:ok, puzzle} =
      Ciphers.create_text_puzzle(scope, %{title: "Note", input_text: "Khoor"}, "caesar")

    {:ok, view, _} = live(conn, ~p"/puzzles/#{puzzle}")

    {:ok, _view, html} =
      view |> element("#make-algorithm") |> render_click() |> follow_redirect(conn)

    assert html =~ "Algorithm created"
    [algorithm] = Algorithms.list_algorithms(scope)

    {:ok, home, _} = live(conn, ~p"/")
    assert has_element?(home, "#algorithm-#{algorithm.id}", "Caesar cipher")
  end

  test "puzzles that can't become an algorithm explain why", %{conn: conn, scope: scope} do
    {:ok, puzzle} =
      Ciphers.create_text_puzzle(scope, %{title: "Clue", input_text: "I CORD"}, "anagram")

    {:ok, view, _} = live(conn, ~p"/puzzles/#{puzzle}")

    assert view |> element("#make-algorithm") |> render_click() =~ "can&#39;t be reversed"
    assert Algorithms.list_algorithms(scope) == []
  end

  test "a deleted or unknown algorithm sends back to the home page", %{conn: conn} do
    for id <- ["999999", "abc"] do
      assert {:error, {:live_redirect, %{to: "/", flash: %{"error" => message}}}} =
               live(conn, "/algorithms/#{id}")

      assert message =~ "doesn't exist"
    end
  end

  test "created from the home page, then edited", %{conn: conn, scope: scope} do
    {:ok, home, _} = live(conn, ~p"/")
    home |> element("#new-algorithm") |> render_click()
    refute has_element?(home, "#new-algorithm-anagram")

    {:error, {:live_redirect, %{to: to}}} =
      home |> element("#new-algorithm-caesar") |> render_click()

    [algorithm] = Algorithms.list_algorithms(scope)
    assert to == "/algorithms/#{algorithm.id}?edit=true"
    assert algorithm.source_puzzle_id == nil

    {:ok, view, _} = live(conn, to)
    assert has_element?(view, "#steps-editor")

    view |> form("#title-form", %{title: "My cipher"}) |> render_change()
    view |> form("#editor-step-form-0", %{index: "0", step: %{shift: "3"}}) |> render_change()
    view |> element("#editor-add-atbash") |> render_click()

    assert has_element?(
             view,
             "#editor-step-1 #editor-step-cipher-1 option[selected][value=atbash]"
           )

    view |> element("#editor-move-up-1") |> render_click()
    assert has_element?(view, "#editor-step-0 option[selected][value=atbash]")
    view |> element("#editor-delete-0") |> render_click()

    # Invalid settings are shown, not saved.
    view |> form("#editor-step-form-0", %{index: "0", step: %{shift: ""}}) |> render_change()
    assert has_element?(view, "#editor-step-form-0 .text-error")

    algorithm = Algorithms.get_algorithm!(algorithm.id)
    assert algorithm.title == "My cipher"
    assert [%{"type" => "caesar", "params" => %{"shift" => 3}}] = algorithm.steps

    view |> element("#done-editing") |> render_click()
    refute has_element?(view, "#steps-editor")
    view |> form("#text-form", %{text: "Hello"}) |> render_change()
    assert view |> element("#stage-text-1") |> render() =~ "Khoor"
  end
end
