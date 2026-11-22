defmodule Subcipher.CiphersTest do
  use Subcipher.DataCase, async: true

  import Subcipher.CipherFixtures
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
               Ciphers.create_puzzle(%{title: "  "}, image, detected_glyphs())
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

  test "list_puzzles/0 and delete_puzzle/1" do
    puzzle = puzzle_fixture()
    [%{symbol_count: 26, solved_count: 0, glyph_count: count}] = Ciphers.list_puzzles()
    assert count == length(pangram_letters())

    file = Path.join(Ciphers.uploads_dir(), Path.basename(hd(puzzle.images).path))
    assert {:ok, _} = Ciphers.delete_puzzle(puzzle)
    refute File.exists?(file)
    assert Ciphers.list_puzzles() == []
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
