defmodule Subcipher.Steps.Alphabet do
  @moduledoc """
  Helpers for letter-wise ciphers over the latin alphabet A–Z.

  Letters are handled as indexes 0..25; case is preserved and any other
  character (digits, punctuation, spaces, "·" for unknown symbols) is left
  untouched.
  """

  @unknown "·"

  def letters, do: Enum.map(?A..?Z, &<<&1>>)
  def unknown, do: @unknown

  @doc """
  Replaces each letter of `text` by `fun.(index)`, where `index` is 0..25.
  `fun` returns the index of the replacement letter, or `nil` when the
  letter can't be decoded (rendered as "#{@unknown}").
  """
  def map_letters(text, fun) do
    for <<c::utf8 <- text>>, into: "" do
      cond do
        c in ?A..?Z -> render(fun.(c - ?A), ?A)
        c in ?a..?z -> render(fun.(c - ?a), ?a)
        true -> <<c::utf8>>
      end
    end
  end

  defp render(nil, _base), do: @unknown
  defp render(index, base) when index in 0..25, do: <<base + index>>

  @doc "Counts the letters (case-insensitive) of `text`: %{\"A\" => 3, ...}."
  def frequencies(text) do
    for <<c::utf8 <- String.upcase(text)>>, c in ?A..?Z, reduce: %{} do
      acc -> Map.update(acc, <<c>>, 1, &(&1 + 1))
    end
  end

  @doc """
  Distinct symbols of `text` (characters other than whitespace and
  "·"), most frequent first: `[{"☀", 4}, ...]`.
  """
  def symbol_frequencies(text) do
    text
    |> String.graphemes()
    |> Enum.reject(&(&1 =~ ~r/^\s$/u or &1 == @unknown))
    |> Enum.frequencies()
    |> Enum.sort_by(fn {symbol, n} -> {-n, symbol} end)
  end

  # Relative frequencies of letters in English text (%), A..Z.
  @english [8.2, 1.5, 2.8, 4.3, 12.7, 2.2, 2.0, 6.1, 7.0, 0.15, 0.77, 4.0, 2.4] ++
             [6.7, 7.5, 1.9, 0.095, 6.0, 6.3, 9.1, 2.8, 0.98, 2.4, 0.15, 2.0, 0.074]

  @doc "Relative frequencies of the letters A..Z in English text, in %."
  def english_percentages, do: @english

  @doc """
  How unlike English `text` is (chi-squared distance of its letter
  frequencies): lower is more English-like. Texts without letters score
  `:infinity`.
  """
  def english_score(text) do
    counts = frequencies(text)
    total = counts |> Map.values() |> Enum.sum()

    if total == 0 do
      :infinity
    else
      letters()
      |> Enum.zip(@english)
      |> Enum.reduce(0.0, fn {letter, pct}, acc ->
        expected = total * pct / 100
        observed = Map.get(counts, letter, 0)
        acc + (observed - expected) ** 2 / expected
      end)
    end
  end

  # Frequent English words of 3+ letters, found even without spaces between
  # words (decoded texts often have none).
  @common_words ~w(THE AND THAT HAVE FOR NOT WITH YOU THIS BUT HIS FROM THEY SAY HER SHE
                   WILL ONE ALL WOULD THERE THEIR WHAT OUT ABOUT WHO GET WHICH WHEN MAKE
                   CAN LIKE TIME JUST HIM KNOW TAKE INTO YOUR SOME COULD THEM SEE OTHER
                   THAN THEN NOW LOOK ONLY COME OVER THINK ALSO BACK AFTER USE TWO HOW OUR
                   WORK FIRST WELL WAY EVEN NEW WANT BECAUSE ANY THESE GIVE DAY MOST ARE WAS
                   HAS HAD WERE BEEN)

  # Frequent English letter pairs.
  @common_bigrams ~w(TH HE IN ER AN RE ON AT EN ND TI ES OR TE OF ED IS IT AL AR ST TO NT NG
                     SE HA AS OU IO LE VE CO ME DE HI RI RO IC NE EA RA CE)

  @doc """
  Common English words (3+ letters) found in `text`, most frequent first,
  whether or not it has spaces between words.
  """
  def common_words(text) do
    letters = String.upcase(text)

    @common_words
    |> Enum.map(&{&1, count_occurrences(letters, &1)})
    |> Enum.filter(fn {_, n} -> n > 0 end)
    # Prefer longer words: "THE" inside "THEY" counts for both.
    |> Enum.sort_by(fn {word, n} -> {-n * String.length(word), word} end)
    |> Enum.map(&elem(&1, 0))
  end

  defp count_occurrences(text, word), do: length(String.split(text, word)) - 1

  @doc """
  Share (0..1) of the letter pairs of `text` (inside words) that are among
  the most frequent English ones. English text is around 0.3–0.4,
  scrambled text much lower.
  """
  def bigram_ratio(text) do
    pairs =
      for word <- String.split(String.upcase(text), ~r/[^A-Z]+/, trim: true),
          [a, b] <- Enum.chunk_every(String.graphemes(word), 2, 1, :discard),
          do: a <> b

    case pairs do
      [] -> 0.0
      pairs -> Enum.count(pairs, &(&1 in @common_bigrams)) / length(pairs)
    end
  end

  @doc """
  Index of coincidence of the letters of `text`: the chance that two letters
  picked at random are the same. English is about 0.066, uniformly random
  letters about 0.038.
  """
  def index_of_coincidence(text) do
    counts = frequencies(text) |> Map.values()
    n = Enum.sum(counts)

    if n < 2,
      do: 0.0,
      else: Enum.sum(Enum.map(counts, &(&1 * (&1 - 1)))) / (n * (n - 1))
  end

  @doc """
  A short explanation of why `text` looks like English: the common words it
  contains, if any. `nil` when nothing notable.
  """
  def words_hint(text) do
    case common_words(text) do
      [] -> nil
      words -> "contains " <> (words |> Enum.take(4) |> Enum.join(", "))
    end
  end

  @doc "Letters A..Z of `text` from most to least frequent (ties alphabetical)."
  def letters_by_frequency(text) do
    text |> frequencies() |> Enum.sort_by(fn {l, n} -> {-n, l} end) |> Enum.map(&elem(&1, 0))
  end

  @doc "English letters from most to least frequent."
  def english_order, do: String.graphemes("ETAOINSHRDLCUMWFGYPBVKJXQZ")
end
