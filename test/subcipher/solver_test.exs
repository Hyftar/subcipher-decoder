defmodule Subcipher.SolverTest do
  use ExUnit.Case, async: true

  alias Subcipher.{English, Solver, Steps}

  @text "It is a truth universally acknowledged that a single man in possession of a good " <>
          "fortune must be in want of a wife However little known the feelings or views of " <>
          "such a man may be on his first entering a neighbourhood this truth is so well fixed"

  # The text as letters 0..25 (with :gap between words if `gaps`), cut to
  # about `n` letters, and encrypted with a random alphabet.
  defp encrypt(n, seed, gaps) do
    words = @text |> String.upcase() |> String.split(~r/[^A-Z]+/, trim: true)

    plain =
      words
      |> Enum.reduce_while([], fn word, acc ->
        if length(Enum.reject(acc, &(&1 == :gap))) >= n,
          do: {:halt, acc},
          else: {:cont, acc ++ [:gap] ++ English.letters(word)}
      end)
      |> tl()
      |> then(fn tokens -> if gaps, do: tokens, else: Enum.reject(tokens, &(&1 == :gap)) end)

    :rand.seed(:exsss, {seed, 99, 5})
    key = Enum.shuffle(0..25) |> List.to_tuple()

    {plain,
     Enum.map(plain, fn
       :gap -> :gap
       l -> elem(key, l)
     end)}
  end

  defp accuracy(plain, cipher, mapping) do
    pairs = Enum.zip(cipher, plain) |> Enum.reject(fn {c, _} -> c == :gap end)
    Enum.count(pairs, fn {c, l} -> mapping[c] == <<?A + l>> end) / length(pairs)
  end

  test "English text scores higher than random letters" do
    english = English.score_per_quadgram(English.letters(@text))
    random = English.score_per_quadgram(for i <- 1..200, do: rem(i * 7 + 3, 26))
    assert english > -4.5 and random < -6
    assert English.word?("truth") and not English.word?("xqzt")
  end

  test "solves a random alphabet from about 150 letters (no word breaks)" do
    for seed <- 1..2 do
      {plain, cipher} = encrypt(150, seed, false)
      assert {:ok, %{mapping: mapping}} = Solver.solve(cipher)
      assert accuracy(plain, cipher, mapping) >= 0.95
    end
  end

  test "word breaks let it solve shorter texts (about 80 letters)" do
    for seed <- 1..2 do
      {plain, cipher} = encrypt(80, seed, true)
      assert {:ok, %{mapping: mapping}} = Solver.solve(cipher)
      assert accuracy(plain, cipher, mapping) >= 0.95
    end
  end

  test "keeps the letters it is given" do
    {_plain, cipher} = encrypt(100, 3, true)
    [first | _] = cipher
    assert {:ok, %{mapping: mapping}} = Solver.solve(cipher, fixed: %{first => "Q"})
    # Fixed symbols are not in the result, and their letter isn't reused.
    refute Map.has_key?(mapping, first)
    refute "Q" in Map.values(mapping)
  end

  test "more symbols than letters, and too-short texts" do
    symbols = Enum.map(1..60, &rem(&1 * 7, 30))
    assert {:ok, %{mapping: mapping}} = Solver.solve(symbols, restarts: 2, iterations: 200)
    assert map_size(mapping) == 30

    assert {:error, :too_short} = Solver.solve([:a, :b, :gap, :c])
  end

  test "explain/1 counts English words" do
    assert Solver.explain("THE GODFATHER ATTACKED US") =~ "3 of 4 words are English words"
  end

  test "mixed alphabet: Try to solve finds the alphabet" do
    {:ok, cipher} = Steps.fetch_cipher("mixed_alphabet")
    {plain, encrypted} = encrypt(90, 4, true)

    to_text = fn tokens ->
      Enum.map_join(tokens, fn
        :gap -> " "
        l -> <<?A + l>>
      end)
    end

    assert {:ok, solution} = Steps.solve(cipher, to_text.(encrypted), %{mapping: %{}})
    assert solution.label == "Solver"
    assert solution.reason =~ "words are English words"
    assert solution.preview == Steps.preview(to_text.(plain))
    refute solution.applied

    assert {:error, message} = Steps.solve(cipher, "AB CD", %{mapping: %{}})
    assert message =~ "Too short"
  end

  test "symbol substitution on text: Try to solve keeps the user's letters" do
    {:ok, cipher} = Steps.fetch_cipher("symbol_substitution")
    {_plain, encrypted} = encrypt(90, 5, true)
    # Encrypted with symbols instead of letters.
    symbols = ~w(☀ ♪ Θ ♠ Φ ☎ ★ ♣ ♥ ♦ ☂ ✈ ⚓ ☯ ⚑ ✿ ☘ ⌘ Ω Δ Ψ Σ Λ Ξ Π Γ)

    text =
      Enum.map_join(encrypted, fn
        :gap -> " "
        l -> Enum.at(symbols, l)
      end)

    first = String.first(text)

    assert {:ok, solution} = Steps.solve(cipher, text, %{mapping: %{first => "I"}})
    assert solution.params.mapping[first] == "I"
    assert solution.reason =~ "Your 1 letter(s) were kept."
    assert solution.preview =~ "IT IS A TRUTH"
  end
end
