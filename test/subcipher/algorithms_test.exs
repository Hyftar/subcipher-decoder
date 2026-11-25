defmodule Subcipher.AlgorithmsTest do
  use Subcipher.DataCase, async: true

  import Subcipher.CipherFixtures
  import Subcipher.AccountsFixtures, only: [user_scope_fixture: 0]
  alias Subcipher.{Algorithms, Ciphers, Steps}
  alias Subcipher.Algorithms.Algorithm

  defp text_puzzle(steps) do
    {:ok, puzzle} =
      Ciphers.create_text_puzzle(
        user_scope_fixture(),
        %{title: "Chain", input_text: "x"},
        "caesar"
      )

    [first] = puzzle.steps
    {:ok, _} = Steps.update_params(first, %{"shift" => "3"})

    for {type, params} <- steps do
      {:ok, step} = Steps.add_step(puzzle, type)
      {:ok, _} = Steps.update_params(step, params)
    end

    Ciphers.get_puzzle!(puzzle.id)
  end

  # The pangram puzzle with its solution as the symbol key.
  defp solved_pictures_puzzle do
    puzzle = puzzle_fixture()

    for {symbol_id, letter} <- solution(puzzle) do
      {:ok, _} = Ciphers.assign_letter(Enum.find(puzzle.symbols, &(&1.id == symbol_id)), letter)
    end

    Ciphers.get_puzzle!(puzzle.id)
  end

  defp final(stages), do: List.last(stages).value

  test "a text puzzle's steps encode and decode any text" do
    puzzle = text_puzzle([{"vigenere", %{"key" => "LEMON"}}, {"atbash", %{}}])
    assert {:ok, algorithm} = Algorithms.create_from_puzzle(user_scope_fixture(), puzzle)
    assert algorithm.input_kind == "text"
    assert length(algorithm.steps) == 3

    encoded = Algorithms.encode(algorithm, "Attack at dawn")
    # Plain text, then the steps from the last to the first.
    assert Enum.map(encoded, & &1.label) ==
             [
               "Plain text",
               "Step 3 · Atbash",
               "Step 2 · Vigenère cipher",
               "Step 1 · Caesar cipher"
             ]

    decoded = Algorithms.decode(algorithm, final(encoded))

    assert Enum.map(decoded, & &1.label) ==
             [
               "Cipher text",
               "Step 1 · Caesar cipher",
               "Step 2 · Vigenère cipher",
               "Step 3 · Atbash"
             ]

    assert final(decoded) == "Attack at dawn"
  end

  test "settings are frozen: later changes to the puzzle don't affect it" do
    puzzle = text_puzzle([])
    {:ok, algorithm} = Algorithms.create_from_puzzle(user_scope_fixture(), puzzle)
    {:ok, _} = Steps.update_params(hd(puzzle.steps), %{"shift" => "10"})

    assert final(Algorithms.encode(Algorithms.get_algorithm!(algorithm.id), "abc")) == "def"
  end

  test "steps that can't be reversed (anagrams) prevent it" do
    puzzle = text_puzzle([{"anagram", %{}}])

    assert [problem] = Algorithms.problems(puzzle)
    assert problem =~ "Step 2 (Anagram) can't be reversed"
    assert {:error, [^problem]} = Algorithms.create_from_puzzle(user_scope_fixture(), puzzle)
  end

  test "a pictures puzzle needs letters in its symbol key" do
    assert ["No symbol has a letter yet" <> _] = Algorithms.problems(puzzle_fixture())
  end

  describe "creating and editing" do
    test "an algorithm made from scratch, edited step by step" do
      assert {:error, :not_reversible} =
               Algorithms.create_algorithm(user_scope_fixture(), "anagram")

      assert {:error, :unknown_cipher} = Algorithms.create_algorithm(user_scope_fixture(), "nope")

      {:ok, algorithm} = Algorithms.create_algorithm(user_scope_fixture(), "caesar")
      assert algorithm.source_puzzle_id == nil and algorithm.input_kind == "text"
      assert [%{"type" => "caesar"}] = algorithm.steps

      {:ok, algorithm} = Algorithms.update_step_params(algorithm, 0, %{"shift" => "3"})
      assert final(Algorithms.decode(algorithm, "KHOOR")) == "HELLO"

      assert {:error, %Ecto.Changeset{}} =
               Algorithms.update_step_params(algorithm, 0, %{"shift" => "x"})

      {:ok, algorithm} = Algorithms.add_step(algorithm, "reverse")
      {:ok, algorithm} = Algorithms.add_step(algorithm, "atbash")
      assert {:error, :not_reversible} = Algorithms.add_step(algorithm, "anagram")
      assert Enum.map(algorithm.steps, & &1["type"]) == ~w(caesar reverse atbash)

      {:ok, algorithm} = Algorithms.move_step(algorithm, 2, :up)
      assert Enum.map(algorithm.steps, & &1["type"]) == ~w(caesar atbash reverse)
      {:ok, algorithm} = Algorithms.change_step_type(algorithm, 1, "vigenere")
      assert %{"type" => "vigenere", "params" => %{"key" => _}} = Enum.at(algorithm.steps, 1)

      {:ok, algorithm} = Algorithms.delete_step(algorithm, 2)
      {:ok, algorithm} = Algorithms.delete_step(algorithm, 1)
      assert {:error, :last_step} = Algorithms.delete_step(algorithm, 0)

      {:ok, algorithm} = Algorithms.rename(algorithm, "  Mine ")
      assert algorithm.title == "Mine"
      assert {:error, :blank} = Algorithms.rename(algorithm, " ")

      # Still encodes and decodes after the edits.
      text = final(Algorithms.encode(algorithm, "Attack at dawn"))
      assert final(Algorithms.decode(algorithm, text)) == "Attack at dawn"
    end

    test "one made from a puzzle can be edited without changing the puzzle" do
      puzzle = text_puzzle([])
      {:ok, algorithm} = Algorithms.create_from_puzzle(user_scope_fixture(), puzzle)
      {:ok, algorithm} = Algorithms.add_step(algorithm, "atbash")

      assert length(algorithm.steps) == 2
      assert length(Ciphers.get_puzzle!(puzzle.id).steps) == 1
      assert algorithm.source_puzzle_id == puzzle.id
    end
  end

  describe "drafts" do
    test "are edited in memory, and saved as a puzzle with their steps" do
      assert {:ok, draft} = Algorithms.new_draft("caesar", %{"shift" => "5"})
      assert Algorithm.draft?(draft)
      assert draft.title == "Caesar cipher"
      assert Algorithms.encode(draft, "abc") |> List.last() |> Map.get(:value) == "fgh"

      {:ok, draft} = Algorithms.add_step(draft, "reverse")
      {:ok, draft} = Algorithms.update_step_params(draft, 0, %{"shift" => "1"})
      assert Algorithm.draft?(draft)
      assert [%{"type" => "caesar"}, %{"type" => "reverse"}] = draft.steps
      assert Subcipher.Repo.aggregate(Algorithm, :count) == 0

      scope = user_scope_fixture()
      {:ok, puzzle} = Algorithms.save_as_puzzle(scope, draft, %{title: "Kept", input_text: "dcb"})
      assert puzzle.user_id == scope.user.id
      assert [%{type: "caesar", position: 1}, %{type: "reverse", position: 2}] = puzzle.steps
      assert List.last(Steps.run(puzzle.input_text, puzzle.steps)).output == "abc"
    end

    test "invalid settings keep the defaults; unknown ciphers are refused" do
      assert {:ok, draft} = Algorithms.new_draft("caesar", %{"shift" => "x"})
      assert [%{"params" => %{"shift" => 3}}] = draft.steps
      assert {:error, :unknown_cipher} = Algorithms.new_draft("enigma")
    end

    test "can't be saved without a cipher text" do
      {:ok, draft} = Algorithms.new_draft("caesar")

      assert {:error, %Ecto.Changeset{}} =
               Algorithms.save_as_puzzle(user_scope_fixture(), draft, %{
                 title: "Empty",
                 input_text: ""
               })

      assert Subcipher.Repo.aggregate(Subcipher.Ciphers.Puzzle, :count) == 0
    end
  end

  describe "pictures" do
    test "the symbol key turns text into symbols and back" do
      puzzle = solved_pictures_puzzle()
      {:ok, caesar} = Steps.add_step(puzzle, "caesar")
      {:ok, _} = Steps.update_params(caesar, %{"shift" => "5"})

      {:ok, algorithm} =
        Algorithms.create_from_puzzle(user_scope_fixture(), Ciphers.get_puzzle!(puzzle.id))

      assert length(algorithm.symbol_key) == 26

      encoded = Algorithms.encode(algorithm, "Hello world")
      assert [_plain, %{label: "Step 2 · Caesar cipher"}, %{kind: :symbols} = symbols] = encoded
      assert Enum.all?(symbols.value, &(match?({:symbol, _}, &1) or &1 == {:char, " "}))

      decoded = Algorithms.decode(algorithm, symbols.value)
      assert [%{kind: :symbols}, %{label: "Step 1 · Symbol substitution"}, last] = decoded
      assert last.value == "HELLO WORLD"
    end

    test "the symbol key uses the chosen samples, as trimmed" do
      puzzle = solved_pictures_puzzle()
      symbol = Enum.find(puzzle.symbols, &(&1.letter == "E"))
      [_, glyph | _] = Enum.filter(puzzle.glyphs, &(&1.symbol_id == symbol.id))
      :ok = Ciphers.set_sample(glyph)

      {:ok, glyph} =
        Ciphers.trim_glyph(glyph, %{x: glyph.x, y: glyph.y, w: glyph.w - 1, h: glyph.h})

      {:ok, algorithm} =
        Algorithms.create_from_puzzle(user_scope_fixture(), Ciphers.get_puzzle!(puzzle.id))

      entry = Enum.find(algorithm.symbol_key, &(&1["letter"] == "E"))

      assert Map.take(entry, ~w(x y w h)) == %{
               "x" => glyph.x,
               "y" => glyph.y,
               "w" => glyph.w,
               "h" => glyph.h
             }
    end

    test "letters without a symbol are reported as missing" do
      puzzle = solved_pictures_puzzle()
      q = Enum.find(puzzle.symbols, &(&1.letter == "Q"))
      {:ok, _} = Ciphers.assign_letter(q, nil)

      {:ok, algorithm} =
        Algorithms.create_from_puzzle(user_scope_fixture(), Ciphers.get_puzzle!(puzzle.id))

      assert [{:symbol, _}, {:missing, "Q"}] = Algorithms.text_to_symbols(algorithm, "aq")
    end

    test "pictures are copied: it survives its puzzle, and is cleaned up" do
      puzzle = solved_pictures_puzzle()
      {:ok, algorithm} = Algorithms.create_from_puzzle(user_scope_fixture(), puzzle)
      [%{"path" => path}] = algorithm.images
      file = Path.join(Ciphers.uploads_dir(), Path.basename(path))

      refute path == hd(puzzle.images).path
      {:ok, _} = Ciphers.delete_puzzle(puzzle)
      assert File.exists?(file)
      assert Algorithms.get_algorithm!(algorithm.id).source_puzzle_id == nil

      {:ok, _} = Algorithms.delete_algorithm(algorithm)
      refute File.exists?(file)
    end
  end
end
