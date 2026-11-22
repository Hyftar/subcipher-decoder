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
      assert File.exists?(Path.join(Ciphers.uploads_dir(), Path.basename(puzzle.image_path)))
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

    file = Path.join(Ciphers.uploads_dir(), Path.basename(puzzle.image_path))
    assert {:ok, _} = Ciphers.delete_puzzle(puzzle)
    refute File.exists?(file)
    assert Ciphers.list_puzzles() == []
  end
end
