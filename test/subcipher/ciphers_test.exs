defmodule Subcipher.CiphersTest do
  use Subcipher.DataCase, async: true

  import Subcipher.CipherFixtures
  import Subcipher.AccountsFixtures, only: [user_scope_fixture: 0]
  alias Subcipher.Ciphers

  describe "create_puzzle/4" do
    test "stores the picture, glyphs and one symbol per distinct cipher symbol" do
      puzzle = puzzle_fixture()

      assert puzzle.title == "Pangram"
      assert length(puzzle.glyphs) == length(pangram_letters())
      assert length(puzzle.symbols) == 26
      assert File.exists?(Path.join(Ciphers.uploads_dir(), Path.basename(hd(puzzle.images).path)))
      assert Ciphers.plaintext(puzzle) =~ "··· ····· ····· ···\n"
    end

    test "requires a title" do
      image = %{path: fixture_path("pangram_clean.png"), ext: ".png", width: 10, height: 10}

      assert {:error, %Ecto.Changeset{}} =
               Ciphers.create_puzzle(
                 user_scope_fixture(),
                 %{title: "  "},
                 image,
                 detected_glyphs()
               )
    end
  end

  test "solving every symbol reveals the plain text" do
    puzzle = puzzle_fixture()

    for {symbol_id, letter} <- solution(puzzle) do
      symbol = Enum.find(puzzle.symbols, &(&1.id == symbol_id))
      {:ok, _} = Ciphers.assign_letter(symbol, String.downcase(letter))
    end

    assert puzzle.id |> Ciphers.get_puzzle!() |> Ciphers.plaintext() == pangram_text()
  end

  test "assign_letter/2 clears with empty values and rejects long ones" do
    [symbol | _] = puzzle_fixture().symbols
    assert {:ok, %{letter: "TH"}} = Ciphers.assign_letter(symbol, " th ")
    assert {:ok, %{letter: nil}} = Ciphers.assign_letter(symbol, "")
    assert {:error, _} = Ciphers.assign_letter(symbol, "abcd")
  end

  test "ignored symbols are left out of the plain text" do
    puzzle = puzzle_fixture()
    for s <- puzzle.symbols, do: Ciphers.set_ignored(s, true)
    assert puzzle.id |> Ciphers.get_puzzle!() |> Ciphers.plaintext() == ""
  end

  test "merge_symbols/2 and detach_glyph/1" do
    puzzle = puzzle_fixture()
    [a, b | _] = puzzle.symbols
    {:ok, b} = Ciphers.assign_letter(b, "x")

    assert {:ok, merged} = Ciphers.merge_symbols(a, b)
    assert merged.letter == "X"

    puzzle = Ciphers.get_puzzle!(puzzle.id)
    assert length(puzzle.symbols) == 25
    glyphs = Enum.filter(puzzle.glyphs, &(&1.symbol_id == a.id))
    assert length(glyphs) >= 2

    assert {:ok, new_symbol} = Ciphers.detach_glyph(hd(glyphs))
    puzzle = Ciphers.get_puzzle!(puzzle.id)
    assert length(puzzle.symbols) == 26
    assert Enum.find(puzzle.glyphs, &(&1.id == hd(glyphs).id)).symbol_id == new_symbol.id

    assert {:error, :only_glyph} =
             Ciphers.detach_glyph(Enum.find(puzzle.glyphs, &(&1.symbol_id == new_symbol.id)))
  end

  describe "samples and trimming" do
    setup do
      puzzle = puzzle_fixture()

      symbol =
        Enum.max_by(puzzle.symbols, &Enum.count(puzzle.glyphs, fn g -> g.symbol_id == &1.id end))

      glyphs = Enum.filter(puzzle.glyphs, &(&1.symbol_id == symbol.id))
      %{puzzle: puzzle, symbol: symbol, glyphs: glyphs}
    end

    test "the sample is the first occurrence until another is chosen", %{
      puzzle: puzzle,
      symbol: symbol,
      glyphs: [first, second | _] = glyphs
    } do
      assert Ciphers.sample_glyph(symbol, glyphs) == first
      assert :ok = Ciphers.set_sample(second)

      puzzle = Ciphers.get_puzzle!(puzzle.id)
      symbol = Enum.find(puzzle.symbols, &(&1.id == symbol.id))
      assert Ciphers.sample_glyph(symbol, glyphs).id == second.id

      # A sample detached from the symbol is no longer its sample.
      {:ok, _} = Ciphers.detach_glyph(second)
      puzzle = Ciphers.get_puzzle!(puzzle.id)
      symbol = Enum.find(puzzle.symbols, &(&1.id == symbol.id))
      remaining = Enum.filter(puzzle.glyphs, &(&1.symbol_id == symbol.id))
      assert Ciphers.sample_glyph(symbol, remaining).id == first.id
    end

    test "regrouping keeps the chosen samples and the trimmed crops", %{
      puzzle: puzzle,
      glyphs: [_, second | _]
    } do
      :ok = Ciphers.set_sample(second)

      {:ok, _} =
        Ciphers.trim_glyph(second, %{"x" => second.x + 1, "y" => second.y, "w" => 3, "h" => 4})

      {:ok, regrouped} = Ciphers.regroup(puzzle, Ciphers.default_threshold())
      glyph = Enum.find(regrouped.glyphs, &(&1.position == second.position))
      assert {glyph.x, glyph.w, glyph.h} == {second.x + 1, 3, 4}

      assert glyph.detected_box == %{
               "x" => second.x,
               "y" => second.y,
               "w" => second.w,
               "h" => second.h
             }

      symbol = Enum.find(regrouped.symbols, &(&1.id == glyph.symbol_id))
      assert symbol.sample_glyph_id == glyph.id
    end

    test "trim_glyph/2 changes the crop inside the picture; reset_glyph_box/1 restores it", %{
      puzzle: puzzle,
      glyphs: [glyph | _]
    } do
      image = Enum.find(puzzle.images, &(&1.id == glyph.image_id))
      detected = %{"x" => glyph.x, "y" => glyph.y, "w" => glyph.w, "h" => glyph.h}

      {:ok, trimmed} =
        Ciphers.trim_glyph(glyph, %{"x" => "#{glyph.x + 2}", "y" => glyph.y, "w" => 5, "h" => 6})

      assert {trimmed.x, trimmed.y, trimmed.w, trimmed.h} == {glyph.x + 2, glyph.y, 5, 6}
      assert trimmed.detected_box == detected

      # Trimming again keeps the box detection found; boxes stay in the picture.
      {:ok, wide} = Ciphers.trim_glyph(trimmed, %{x: -10, y: glyph.y, w: image.width + 50, h: 0})
      assert {wide.x, wide.w, wide.h} == {0, image.width, 1}
      assert wide.detected_box == detected

      assert {:error, :invalid_box} =
               Ciphers.trim_glyph(wide, %{"x" => "a", "y" => 1, "w" => 1, "h" => 1})

      {:ok, reset} = Ciphers.reset_glyph_box(wide)
      assert {reset.x, reset.y, reset.w, reset.h} == {glyph.x, glyph.y, glyph.w, glyph.h}
      assert reset.detected_box == nil
    end
  end

  test "regroup/2 re-clusters and keeps unanimous letters" do
    puzzle = puzzle_fixture()

    for {symbol_id, letter} <- solution(puzzle) do
      Ciphers.assign_letter(Enum.find(puzzle.symbols, &(&1.id == symbol_id)), letter)
    end

    {:ok, everything} = Ciphers.regroup(puzzle, 10.0)
    assert [%{letter: nil}] = everything.symbols

    {:ok, regrouped} = Ciphers.regroup(everything, Ciphers.default_threshold())
    assert length(regrouped.symbols) == 26
    assert regrouped.threshold == Ciphers.default_threshold()

    # Letters were lost when everything was merged; regrouping a solved
    # puzzle with the same threshold keeps them.
    for {symbol_id, letter} <- solution(regrouped) do
      Ciphers.assign_letter(Enum.find(regrouped.symbols, &(&1.id == symbol_id)), letter)
    end

    {:ok, again} = Ciphers.regroup(regrouped, Ciphers.default_threshold())
    assert Ciphers.plaintext(again) == pangram_text()
  end

  test "list_puzzles/1 and delete_puzzle/1" do
    scope = user_scope_fixture()
    puzzle = puzzle_fixture(scope)
    [%{symbol_count: 26, solved_count: 0, glyph_count: count}] = Ciphers.list_puzzles(scope)
    assert Ciphers.list_puzzles(user_scope_fixture()) == []
    assert Ciphers.list_puzzles(nil) == []
    assert count == length(pangram_letters())

    file = Path.join(Ciphers.uploads_dir(), Path.basename(hd(puzzle.images).path))
    assert {:ok, _} = Ciphers.delete_puzzle(puzzle)
    refute File.exists?(file)
    assert Ciphers.list_puzzles(scope) == []
  end

  describe "multiple pictures" do
    defp solve(puzzle) do
      for {symbol_id, letter} <- solution(puzzle) do
        Ciphers.assign_letter(Enum.find(puzzle.symbols, &(&1.id == symbol_id)), letter)
      end

      Ciphers.get_puzzle!(puzzle.id)
    end

    test "symbols are shared: letters found apply to the new picture" do
      puzzle = puzzle_fixture() |> solve()

      assert {:ok, puzzle, %{glyphs: 67, new_symbols: 0}} =
               Ciphers.add_image(
                 puzzle,
                 image_upload("pangram_photo"),
                 detected_glyphs("pangram_photo")
               )

      assert length(puzzle.images) == 2
      assert length(puzzle.symbols) == 26
      assert Enum.map(puzzle.images, & &1.position) == [0, 1]
      assert Ciphers.plaintext(puzzle) == pangram_text() <> "\n\n" <> pangram_text()
    end

    test "unknown symbols in the new picture become new symbols" do
      puzzle = puzzle_fixture()

      assert {:ok, puzzle, %{new_symbols: 18}} =
               Ciphers.add_image(
                 puzzle,
                 image_upload("pixel_glyphs"),
                 detected_glyphs("pixel_glyphs")
               )

      assert length(puzzle.symbols) == 26 + 18
    end

    test "user corrections are kept when adding a picture" do
      puzzle = puzzle_fixture()
      [a, b | _] = puzzle.symbols
      {:ok, _} = Ciphers.merge_symbols(a, b)

      puzzle = add_image_fixture(puzzle, "pangram_photo")
      assert length(puzzle.symbols) == 25
    end

    test "delete_image/1 removes the picture, its glyphs and its own symbols" do
      puzzle = puzzle_fixture() |> add_image_fixture("pixel_glyphs")
      [first, second] = puzzle.images
      file = Path.join(Ciphers.uploads_dir(), Path.basename(second.path))

      assert {:ok, puzzle} = Ciphers.delete_image(second)
      assert length(puzzle.symbols) == 26
      assert length(puzzle.glyphs) == length(pangram_letters())
      refute File.exists?(file)

      assert {:error, :last_image} = Ciphers.delete_image(first)
    end

    test "regroup/2 groups symbols across pictures" do
      puzzle = puzzle_fixture() |> solve() |> add_image_fixture("pangram_photo")

      {:ok, regrouped} = Ciphers.regroup(puzzle, Ciphers.default_threshold())
      assert length(regrouped.symbols) == 26
      assert Ciphers.plaintext(regrouped) == pangram_text() <> "\n\n" <> pangram_text()
    end

    test "reorder_images/2 and move_image/2 change the reading order" do
      puzzle = puzzle_fixture() |> add_image_fixture("pixel_glyphs")
      [pangram, pixels] = Enum.map(puzzle.images, & &1.id)
      pangram_part = Ciphers.plaintext(puzzle) |> String.split("\n\n") |> hd()

      assert {:ok, puzzle} = Ciphers.reorder_images(puzzle, [pixels, pangram])
      assert Enum.map(puzzle.images, & &1.id) == [pixels, pangram]
      assert Enum.map(puzzle.images, & &1.position) == [0, 1]
      # Glyphs (hence the text) follow the pictures' order.
      assert hd(puzzle.glyphs).image_id == pixels
      assert Ciphers.plaintext(puzzle) |> String.split("\n\n") |> List.last() == pangram_part

      pangram_image = Enum.find(puzzle.images, &(&1.id == pangram))
      assert {:ok, puzzle} = Ciphers.move_image(pangram_image, :up)
      assert Enum.map(puzzle.images, & &1.id) == [pangram, pixels]

      # Already first: nothing changes.
      assert {:ok, puzzle} = Ciphers.move_image(hd(puzzle.images), :up)
      assert Enum.map(puzzle.images, & &1.id) == [pangram, pixels]

      assert {:error, :invalid_order} = Ciphers.reorder_images(puzzle, [pangram])
      assert {:error, :invalid_order} = Ciphers.reorder_images(puzzle, [pangram, pangram])
    end

    test "delete_puzzle/1 removes every picture" do
      puzzle = puzzle_fixture() |> add_image_fixture("pangram_photo")
      files = Enum.map(puzzle.images, &Path.join(Ciphers.uploads_dir(), Path.basename(&1.path)))

      assert {:ok, _} = Ciphers.delete_puzzle(puzzle)
      refute Enum.any?(files, &File.exists?/1)
    end
  end
end
