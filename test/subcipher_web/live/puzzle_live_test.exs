defmodule SubcipherWeb.PuzzleLiveTest do
  use SubcipherWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Subcipher.CipherFixtures

  describe "Index" do
    test "symbol substitution asks for a picture, then creates a puzzle", %{conn: conn} do
      {:ok, view, _} = live(conn, ~p"/")
      assert has_element?(view, "#choose-cipher")
      refute has_element?(view, "#new-puzzle-form")

      view |> element("#new-cipher-symbol_substitution") |> render_click()
      assert_patch(view, ~p"/?cipher=symbol_substitution")
      refute has_element?(view, "#choose-cipher")
      assert has_element?(view, "#new-puzzle-input", "Symbol substitution")

      image =
        file_input(view, "#new-puzzle-form", :image, [
          %{
            name: "secret.png",
            content: File.read!(fixture_path("pangram_clean.png")),
            type: "image/png"
          }
        ])

      assert render_upload(image, "secret.png") =~ "secret.png"

      # What the GlyphDetector hook sends once it has analysed the picture.
      view |> element("#new-puzzle-dropzone") |> render_hook("detecting", %{})
      assert render(view) =~ "Detecting symbols"

      view |> element("#new-puzzle-dropzone") |> render_hook("detected", detection_payload())
      assert render(view) =~ "67 symbols detected"

      {:ok, show, html} =
        view
        |> form("#new-puzzle-form", picture: %{title: ""})
        |> render_submit()
        |> follow_redirect(conn)

      assert html =~ "secret"
      assert html =~ "0 / 26 symbols"
      assert has_element?(show, "#symbol-key li", "×")
    end

    test "cannot submit when the picture itself was rejected", %{conn: conn} do
      {:ok, view, _} = live(conn, ~p"/?cipher=symbol_substitution")

      view
      |> file_input("#new-puzzle-form", :image, [
        %{name: "secret.txt", content: "not a picture", type: "text/plain"}
      ])
      |> render_upload("secret.txt")

      # The browser could still decode it and report symbols.
      view |> element("#new-puzzle-dropzone") |> render_hook("detected", detection_payload())

      assert render(view) =~ "Unsupported file type"
      assert has_element?(view, "#new-puzzle-form button[disabled]", "Start decoding")
    end

    test "reports pictures without symbols", %{conn: conn} do
      {:ok, view, _} = live(conn, ~p"/?cipher=symbol_substitution")

      view
      |> element("#new-puzzle-dropzone")
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

  describe "Show of a missing puzzle" do
    test "sends back to the home page", %{conn: conn} do
      for id <- ["999999", "abc"] do
        assert {:error, {:live_redirect, %{to: "/", flash: %{"error" => message}}}} =
                 live(conn, "/puzzles/#{id}")

        assert message =~ "doesn't exist"
      end
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

    test "← / → move through the characters of the text", %{conn: conn, puzzle: puzzle} do
      [g0, g1, g2 | _] = puzzle.glyphs
      last = List.last(puzzle.glyphs)
      {:ok, view, _} = live(conn, ~p"/puzzles/#{puzzle}")
      key = fn k -> view |> element("#puzzle") |> render_hook("key", %{"key" => k}) end
      at? = fn g -> has_element?(view, ~s(#puzzle[data-scroll-to="glyph-#{g.id}"])) end

      # Nothing selected: → starts at the first character, ← at the last.
      key.("ArrowLeft")
      assert at?.(last)
      key.("Escape")

      key.("ArrowRight")
      assert at?.(g0)
      key.("ArrowRight")
      assert at?.(g1)
      key.("ArrowLeft")
      key.("ArrowLeft")
      # Stops at the first character (no wrapping).
      assert at?.(g0)

      # The character's symbol is selected: typing substitutes all of them.
      key.("t")
      assert view |> element("#plaintext") |> render() =~ "T··"

      # Ignored symbols are skipped.
      view |> element("#glyph-#{g1.id}") |> render_click()
      view |> element("#selection-bar button", "Ignore") |> render_click()
      view |> element("#glyph-#{g0.id}") |> render_click()
      key.("ArrowRight")
      assert at?.(g2)
    end

    test "↑ / ↓ move through the symbol key", %{conn: conn, puzzle: puzzle} do
      {:ok, view, _} = live(conn, ~p"/puzzles/#{puzzle}")
      [first, second | _] = for %{symbol: s} <- :sys.get_state(view.pid).socket.assigns.key, do: s
      key = fn k -> view |> element("#puzzle") |> render_hook("key", %{"key" => k}) end
      on_key? = fn s -> has_element?(view, ~s(#puzzle[data-scroll-to="symbol-#{s.id}"])) end

      key.("ArrowDown")
      assert on_key?.(first)
      key.("ArrowDown")
      assert on_key?.(second)
      key.("ArrowUp")
      assert on_key?.(first)

      # → from a symbol picked in the key goes to its first occurrence.
      key.("ArrowRight")
      occurrence = Enum.find(puzzle.glyphs, &(&1.symbol_id == first.id))
      assert has_element?(view, ~s(#puzzle[data-scroll-to="glyph-#{occurrence.id}"]))
    end

    test "merge combines two symbols", %{conn: conn, puzzle: puzzle} do
      {:ok, view, _} = live(conn, ~p"/puzzles/#{puzzle}")
      view |> element("#puzzle") |> render_hook("key", %{"key" => "ArrowDown"})
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

  describe "Show with several pictures" do
    test "adds a picture whose symbols match the existing ones", %{conn: conn} do
      puzzle = puzzle_fixture()
      [first | _] = puzzle.glyphs
      {:ok, view, _} = live(conn, ~p"/puzzles/#{puzzle}")

      # Solve one symbol first: it must apply to the new picture too.
      view |> element("#glyph-#{first.id}") |> render_click()
      view |> element("#puzzle") |> render_hook("key", %{"key" => "t"})

      view |> element("#add-picture button", "Add a picture") |> render_click()

      view
      |> file_input("#add-picture-upload-form", :image, [
        %{
          name: "page2.png",
          content: File.read!(fixture_path("pangram_photo.png")),
          type: "image/png"
        }
      ])
      |> render_upload("page2.png")

      view
      |> element("#add-picture-upload-dropzone")
      |> render_hook("detected", detection_payload("pangram_photo"))

      view |> form("#add-picture-upload-form") |> render_submit()
      # The component notifies the page with send/2: rendered on the next diff.
      assert render(view) =~ "Picture added: 67 glyphs, all matching known symbols."

      assert has_element?(view, "#cipher-text", "Picture 2")
      assert view |> element("#progress") |> render() =~ "1 / 26"

      assert view |> element("#plaintext") |> render() =~
               "T·· ····· ····· ···\n····· ···· T·· ···· ···\n···· ·· ··· ··T· ····\n····· ······ ····\n\nT··"
    end

    test "reorders pictures", %{conn: conn} do
      puzzle = puzzle_fixture() |> add_image_fixture("pixel_glyphs")
      [first, second] = puzzle.images
      {:ok, view, _} = live(conn, ~p"/puzzles/#{puzzle}")

      order = fn ->
        Regex.scan(~r/id="section-(\d+)"/, render(view), capture: :all_but_first)
        |> List.flatten()
        |> Enum.map(&String.to_integer/1)
      end

      assert order.() == [first.id, second.id]
      assert has_element?(view, "#move-up-#{first.id}[disabled]")
      assert has_element?(view, "#move-down-#{second.id}[disabled]")

      view |> element("#move-down-#{first.id}") |> render_click()
      assert order.() == [second.id, first.id]
      assert has_element?(view, "#section-#{second.id}", "Picture 1")

      # Same controls in the original pictures panel.
      view |> element("button", "Original pictures") |> render_click()
      view |> element("#picture-#{first.id} button[aria-label*=up]") |> render_click()
      assert order.() == [first.id, second.id]
    end

    test "→ continues from one picture into the next", %{conn: conn} do
      puzzle = puzzle_fixture() |> add_image_fixture("pixel_glyphs")
      [first_image, second_image] = puzzle.images

      last_of_first =
        puzzle.glyphs |> Enum.filter(&(&1.image_id == first_image.id)) |> List.last()

      first_of_second = Enum.find(puzzle.glyphs, &(&1.image_id == second_image.id))

      {:ok, view, _} = live(conn, ~p"/puzzles/#{puzzle}")
      view |> element("#glyph-#{last_of_first.id}") |> render_click()
      view |> element("#puzzle") |> render_hook("key", %{"key" => "ArrowRight"})
      assert has_element?(view, ~s(#puzzle[data-scroll-to="glyph-#{first_of_second.id}"]))
    end

    test "removes a picture", %{conn: conn} do
      puzzle = puzzle_fixture() |> add_image_fixture("pixel_glyphs")
      [_, second] = puzzle.images
      {:ok, view, _} = live(conn, ~p"/puzzles/#{puzzle}")
      assert view |> element("#progress") |> render() =~ "0 / 44"

      view |> element("button", "Original pictures") |> render_click()
      view |> element("#picture-#{second.id} button", "Remove") |> render_click()

      assert view |> element("#progress") |> render() =~ "0 / 26"
      refute has_element?(view, "#section-#{second.id}")
    end
  end
end
