defmodule SubcipherWeb.PuzzleLiveTest do
  use SubcipherWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Subcipher.CipherFixtures

  describe "Index" do
    test "uploads a picture and creates a puzzle", %{conn: conn} do
      {:ok, view, html} = live(conn, ~p"/")
      assert html =~ "Crack a substitution cipher"

      image =
        file_input(view, "#upload-form", :image, [
          %{
            name: "secret.png",
            content: File.read!(fixture_path("pangram_clean.png")),
            type: "image/png"
          }
        ])

      assert render_upload(image, "secret.png") =~ "secret.png"

      # What the GlyphDetector hook sends once it has analysed the picture.
      view |> element("#dropzone") |> render_hook("detecting", %{})
      assert render(view) =~ "Detecting symbols"

      view |> element("#dropzone") |> render_hook("detected", detection_payload())
      assert render(view) =~ "67 symbols detected"

      {:ok, show, html} =
        view
        |> form("#upload-form", puzzle: %{title: ""})
        |> render_submit()
        |> follow_redirect(conn)

      assert html =~ "secret"
      assert html =~ "0 / 26 symbols"
      assert has_element?(show, "#symbol-key li", "×")
    end

    test "reports pictures without symbols", %{conn: conn} do
      {:ok, view, _} = live(conn, ~p"/")

      view
      |> element("#dropzone")
      |> render_hook("detected", %{"width" => 10, "height" => 10, "glyphs" => []})

      assert render(view) =~ "No symbols were found"
    end

    test "lists and deletes puzzles", %{conn: conn} do
      puzzle = puzzle_fixture()
      {:ok, view, html} = live(conn, ~p"/")
      assert html =~ "Pangram"

      view |> element("#puzzle-#{puzzle.id} button", "") |> render_click()
      refute has_element?(view, "#puzzle-#{puzzle.id}")
    end
  end

  describe "Show" do
    setup do
      puzzle = puzzle_fixture()
      %{puzzle: puzzle, solution: solution(puzzle)}
    end

    test "typing a letter substitutes every identical symbol", %{conn: conn, puzzle: puzzle} do
      {:ok, view, _} = live(conn, ~p"/puzzles/#{puzzle}")

      # First glyph is the cipher symbol for "T" (THE QUICK...), which appears 3 times.
      [first | _] = puzzle.glyphs
      view |> element("#glyph-#{first.id}") |> render_click()
      assert has_element?(view, "#selection-bar", "3 occurrences")

      view |> element("#puzzle") |> render_hook("key", %{"key" => "t"})

      assert view |> element("#plaintext") |> render() =~ "T·· ····· ····· ···"
      assert view |> element("#progress") |> render() =~ "1 / 26"

      same = Enum.filter(puzzle.glyphs, &(&1.symbol_id == first.symbol_id))
      for g <- same, do: assert(has_element?(view, "#glyph-#{g.id}", "T"))

      view |> element("#puzzle") |> render_hook("key", %{"key" => "Backspace"})
      assert view |> element("#progress") |> render() =~ "0 / 26"
    end

    test "solving with the symbol key reveals the message", %{
      conn: conn,
      puzzle: puzzle,
      solution: solution
    } do
      {:ok, view, _} = live(conn, ~p"/puzzles/#{puzzle}")

      for {symbol_id, letter} <- solution do
        view
        |> form("#assign-#{symbol_id}", %{letter: letter})
        |> render_change()
      end

      assert view |> element("#plaintext") |> render() =~ "THE QUICK BROWN FOX\nJUMPS OVER"
      assert view |> element("#progress") |> render() =~ "26 / 26"
    end

    test "warns when a letter is used by several symbols", %{conn: conn, puzzle: puzzle} do
      [a, b | _] = puzzle.symbols
      {:ok, view, _} = live(conn, ~p"/puzzles/#{puzzle}")
      view |> form("#assign-#{a.id}", %{letter: "e"}) |> render_change()
      view |> form("#assign-#{b.id}", %{letter: "e"}) |> render_change()
      assert render(view) =~ "Used by several symbols: E"
    end

    test "arrow keys walk through symbols and merge combines two", %{conn: conn, puzzle: puzzle} do
      {:ok, view, _} = live(conn, ~p"/puzzles/#{puzzle}")
      view |> element("#puzzle") |> render_hook("key", %{"key" => "ArrowRight"})
      assert has_element?(view, "#selection-bar")

      view |> element("#merge-button") |> render_click()
      assert render(view) =~ "Click another symbol to merge"

      [_, %{symbol: other} | _] = :sys.get_state(view.pid).socket.assigns.key
      view |> element("#symbol-#{other.id} button") |> render_click()
      assert view |> element("#progress") |> render() =~ "0 / 25"
    end

    test "split a glyph off its symbol", %{conn: conn, puzzle: puzzle} do
      {:ok, view, _} = live(conn, ~p"/puzzles/#{puzzle}")
      [first | _] = puzzle.glyphs
      view |> element("#glyph-#{first.id}") |> render_click()
      view |> element("#detach-button") |> render_click()
      assert view |> element("#progress") |> render() =~ "0 / 27"
    end

    test "renames the puzzle", %{conn: conn, puzzle: puzzle} do
      {:ok, view, _} = live(conn, ~p"/puzzles/#{puzzle}")
      view |> form("#title-form", puzzle: %{title: "Renamed"}) |> render_submit()
      assert page_title(view) =~ "Renamed"
    end
  end
end
