defmodule SubcipherWeb.AlgorithmLiveTest do
  use SubcipherWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Subcipher.CipherFixtures

  alias Subcipher.{Algorithms, Ciphers, Steps}

  defp text_algorithm do
    {:ok, puzzle} = Ciphers.create_text_puzzle(%{title: "Secret", input_text: "x"}, "caesar")
    {:ok, _} = Steps.update_params(hd(puzzle.steps), %{"shift" => "3"})
    {:ok, algorithm} = Algorithms.create_from_puzzle(Ciphers.get_puzzle!(puzzle.id))
    algorithm
  end

  test "encode and decode, with the text after each step", %{conn: conn} do
    algorithm = text_algorithm()
    {:ok, view, _} = live(conn, ~p"/algorithms/#{algorithm}")

    assert has_element?(view, "#algorithm-step-1", "Caesar cipher")
    assert has_element?(view, "#mode-encode[aria-selected=true]")

    view |> form("#text-form", %{text: "Hello"}) |> render_change()
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

  test "a pictures algorithm draws symbols, and decodes clicked symbols", %{conn: conn} do
    puzzle = puzzle_fixture()

    for {symbol_id, letter} <- solution(puzzle) do
      {:ok, _} = Ciphers.assign_letter(Enum.find(puzzle.symbols, &(&1.id == symbol_id)), letter)
    end

    {:ok, algorithm} = Algorithms.create_from_puzzle(Ciphers.get_puzzle!(puzzle.id))
    {:ok, view, _} = live(conn, ~p"/algorithms/#{algorithm}")

    view |> form("#text-form", %{text: "hi"}) |> render_change()
    assert %{"lines" => [[%{"t" => "glyph"}, %{"t" => "glyph"}]]} = image_spec(view)

    {:ok, view, _} = live(conn, ~p"/algorithms/#{algorithm}?mode=decode")
    refute has_element?(view, "#text-form")
    h = Enum.find_index(algorithm.symbol_key, &(&1["letter"] == "H"))
    i = Enum.find_index(algorithm.symbol_key, &(&1["letter"] == "I"))

    view |> element("#key-#{h}") |> render_click()
    view |> element("#key-#{i}") |> render_click()
    assert view |> element("#stage-text-1") |> render() =~ "HI"

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

  test "the encoded image: lines, style, alignment and colours", %{conn: conn} do
    puzzle = puzzle_fixture()

    for {symbol_id, letter} <- solution(puzzle) do
      {:ok, _} = Ciphers.assign_letter(Enum.find(puzzle.symbols, &(&1.id == symbol_id)), letter)
    end

    {:ok, algorithm} = Algorithms.create_from_puzzle(Ciphers.get_puzzle!(puzzle.id))
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

  test "space and new line keys of the symbol keyboard", %{conn: conn} do
    puzzle = puzzle_fixture()

    for {symbol_id, letter} <- solution(puzzle) do
      {:ok, _} = Ciphers.assign_letter(Enum.find(puzzle.symbols, &(&1.id == symbol_id)), letter)
    end

    {:ok, algorithm} = Algorithms.create_from_puzzle(Ciphers.get_puzzle!(puzzle.id))
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

  test "made from the puzzle page, listed on the home page", %{conn: conn} do
    {:ok, puzzle} = Ciphers.create_text_puzzle(%{title: "Note", input_text: "Khoor"}, "caesar")
    {:ok, view, _} = live(conn, ~p"/puzzles/#{puzzle}")

    {:ok, _view, html} =
      view |> element("#make-algorithm") |> render_click() |> follow_redirect(conn)

    assert html =~ "Algorithm created"
    [algorithm] = Algorithms.list_algorithms()

    {:ok, home, _} = live(conn, ~p"/")
    assert has_element?(home, "#algorithm-#{algorithm.id}", "Caesar cipher")
  end

  test "puzzles that can't become an algorithm explain why", %{conn: conn} do
    {:ok, puzzle} = Ciphers.create_text_puzzle(%{title: "Clue", input_text: "I CORD"}, "anagram")
    {:ok, view, _} = live(conn, ~p"/puzzles/#{puzzle}")

    assert view |> element("#make-algorithm") |> render_click() =~ "can&#39;t be reversed"
    assert Algorithms.list_algorithms() == []
  end

  test "a deleted or unknown algorithm sends back to the home page", %{conn: conn} do
    for id <- ["999999", "abc"] do
      assert {:error, {:live_redirect, %{to: "/", flash: %{"error" => message}}}} =
               live(conn, "/algorithms/#{id}")

      assert message =~ "doesn't exist"
    end
  end
end
