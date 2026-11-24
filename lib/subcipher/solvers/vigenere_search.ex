defmodule Subcipher.Solvers.VigenereSearch do
  @moduledoc """
  Finds the key of a Vigenère cipher (`Subcipher.Steps.Ciphers.Vigenere`).

  Two kinds of keys are tried, and compared by how English the text reads
  (`Subcipher.English.text_score/1`) minus the size of the key space they
  come from (`Subcipher.KeySpace.word/1`: a dictionary word costs ≈ 4.3, a
  free key 1.4 per letter), so a long free key must fit much better:

    * every dictionary word (and the `:known` keys): what cracks short
      texts, where statistics say little;
    * for the likeliest key lengths (letters that many apart repeat like
      English, the index of coincidence, and the spacing of repeated
      sequences, the Kasiski test), the key letter making each column most
      English-like, then each key letter improved in turn against the
      whole text until nothing improves.
  """

  alias Subcipher.{English, KeySpace}

  @max_length 30
  @ioc_lengths 6
  @kasiski_lengths 3
  @max_passes 6

  @english Subcipher.Steps.Alphabet.english_percentages() |> Enum.map(&(&1 / 100))

  @doc """
  The best key (a string) for the cipher text `words` (lists of cipher
  letters 0..25). Options: `:known` (extra keys to try), `:starts` (keys to
  improve letter by letter too, e.g. the current one).
  """
  def search(words, opts \\ []) do
    letters = List.flatten(words)

    dictionary_keys =
      Enum.map(Keyword.get(opts, :known, []), &English.letters/1) ++ English.dictionary(2, 15)

    given =
      opts |> Keyword.get(:starts, []) |> Enum.map(&English.letters/1) |> Enum.reject(&(&1 == []))

    candidates =
      [best_of(words, dictionary_keys)] ++
        Enum.map(given, &refine(words, &1)) ++
        for length <- key_lengths(letters), do: refine(words, initial_key(letters, length))

    {key, _score} = Enum.max_by(candidates, fn {key, score} -> score - KeySpace.word(key) end)
    key
  end

  defp best_of(words, keys) do
    {key, score} = keys |> Enum.map(&{&1, score(words, &1)}) |> Enum.max_by(&elem(&1, 1))
    {letters_to_string(key), score}
  end

  @doc "The score of decoding `words` with `key` (a list of shifts 0..25)."
  def score(words, key), do: words |> decode(List.to_tuple(key)) |> English.text_score()

  defp decode(words, key) do
    size = tuple_size(key)

    {decoded, _} =
      Enum.map_reduce(words, 0, fn word, i ->
        {letters, i} =
          Enum.map_reduce(word, i, fn letter, i ->
            {rem(letter - elem(key, rem(i, size)) + 26, 26), i + 1}
          end)

        {letters, i}
      end)

    decoded
  end

  defp letters_to_string(key), do: for(l <- key, into: "", do: <<?A + l>>)

  ## Key lengths

  defp key_lengths(letters) do
    max = min(@max_length, div(length(letters), 3)) |> max(1)

    by_ioc =
      1..max
      |> Enum.sort_by(fn length -> -mean_ioc(columns(letters, length)) end)
      |> Enum.take(@ioc_lengths)

    Enum.uniq(Enum.to_list(1..min(3, max)) ++ by_ioc ++ kasiski(letters, max))
  end

  defp columns(letters, length) do
    letters
    |> Enum.with_index()
    |> Enum.group_by(fn {_, i} -> rem(i, length) end, &elem(&1, 0))
    |> Enum.sort()
    |> Enum.map(&elem(&1, 1))
  end

  defp mean_ioc(columns) do
    iocs =
      for column <- columns do
        n = length(column)
        counts = column |> Enum.frequencies() |> Map.values()
        if n < 2, do: 0.0, else: Enum.sum(Enum.map(counts, &(&1 * (&1 - 1)))) / (n * (n - 1))
      end

    Enum.sum(iocs) / length(iocs)
  end

  # Repeated 3-letter sequences are often the same plain text under the
  # same key letters: their distances are multiples of the key length.
  defp kasiski(letters, max) do
    distances =
      letters
      |> Enum.chunk_every(3, 1, :discard)
      |> Enum.with_index()
      |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))
      |> Enum.flat_map(fn {_, positions} ->
        for [a, b] <- Enum.chunk_every(positions, 2, 1, :discard), do: b - a
      end)

    if distances == [] do
      []
    else
      2..max//1
      |> Enum.map(fn length -> {length, Enum.count(distances, &(rem(&1, length) == 0))} end)
      |> Enum.filter(fn {_, count} -> count > 0 end)
      # Small lengths divide everything: favour the larger ones explaining
      # nearly as much.
      |> Enum.sort_by(fn {length, count} -> -count * :math.sqrt(length) end)
      |> Enum.take(@kasiski_lengths)
      |> Enum.map(&elem(&1, 0))
    end
  end

  ## Keys

  # Each key letter: the shift giving its column the closest letter
  # frequencies to English.
  defp initial_key(letters, length) do
    for column <- columns(letters, length) do
      counts = Enum.frequencies(column)
      n = length(column)

      Enum.min_by(0..25, fn shift ->
        @english
        |> Enum.with_index()
        |> Enum.reduce(0.0, fn {p, plain}, acc ->
          expected = n * p
          observed = Map.get(counts, rem(plain + shift, 26), 0)
          acc + (observed - expected) ** 2 / expected
        end)
      end)
    end
  end

  # Coordinate ascent: each key letter in turn takes the shift reading best
  # with the whole text, until a pass improves nothing.
  defp refine(words, key) do
    {key, score} =
      Enum.reduce_while(1..@max_passes, {key, score(words, key)}, fn _, {key, score} ->
        {improved, improved_score} =
          Enum.reduce(0..(length(key) - 1), {key, score}, fn i, {key, score} ->
            0..25
            |> Enum.map(fn shift ->
              candidate = List.replace_at(key, i, shift)
              {candidate, score(words, candidate)}
            end)
            |> Enum.max_by(&elem(&1, 1))
            |> then(fn {candidate, s} -> if s > score, do: {candidate, s}, else: {key, score} end)
          end)

        if improved_score > score,
          do: {:cont, {improved, improved_score}},
          else: {:halt, {key, score}}
      end)

    {letters_to_string(key), score}
  end
end
