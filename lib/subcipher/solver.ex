defmodule Subcipher.Solver do
  @moduledoc """
  Solves monoalphabetic substitution ciphers: finds the letter of each
  symbol making the text read most like English (`Subcipher.English`).

  The search is simulated annealing with random restarts: starting from a
  letter assignment, it keeps swapping the letters of two symbols (or giving
  a symbol an unused letter), keeping changes that read more like English
  and, early on, some that read slightly worse (to get out of dead ends). It
  remembers the best assignment over all restarts. Seeded, so the same input
  gives the same result.

  On English texts encrypted with random alphabets, it solves texts of 70+
  letters, in about a second for 150 letters (tuned with
  `test/subcipher/solver_test.exs`). Below about 60 letters, statistics are
  too weak and results are partial.

  It works on any symbols (picture symbol ids, characters…): give it the
  text as a list of symbols in reading order, with `:gap` between words when
  word breaks are known. Words then count too: dictionary words make a
  solution more likely (`Subcipher.English.words_score/1`).
  """

  alias Subcipher.English

  @english_order ~c"ETAOINSHRDLCUMWFGYPBVKJXQZ" |> Enum.map(&(&1 - ?A))

  @doc """
  Solves `symbols` (the cipher text as a list of symbols, in order).

  Options:
    * `:fixed` - `%{symbol => letter}` already known (letters "A".."Z"),
      kept as they are;
    * `:restarts` (default 30, fewer for long texts), `:iterations` per
      restart (default 5000), `:temperature` (default 6.0, 0 for a plain
      hill climb);
    * `:seed` (default 1).

  Returns `%{mapping: %{symbol => "A".."Z"}, score: per_quadgram}`, or
  `{:error, :too_short}` below 8 letters.
  """
  def solve(symbols, opts \\ []) do
    fixed = opts |> Keyword.get(:fixed, %{}) |> Map.new(fn {s, <<l>>} -> {s, l - ?A} end)
    # Long texts are easy and slow to score: fewer restarts.
    restarts =
      Keyword.get(
        opts,
        :restarts,
        length(symbols) |> max(1) |> then(&div(4500, &1)) |> min(30) |> max(6)
      )

    iterations = Keyword.get(opts, :iterations, 5000)
    temperature = Keyword.get(opts, :temperature, 6.0)
    :rand.seed(:exsss, {Keyword.get(opts, :seed, 1), 7, 13})

    word_weight = Keyword.get(opts, :word_weight, 1.0)
    letter_count = Enum.count(symbols, &(&1 != :gap))
    free = symbols |> Enum.reject(&(&1 == :gap or Map.has_key?(fixed, &1))) |> Enum.frequencies()
    # The free symbols, most frequent first, as indexes 0..k-1.
    free_symbols =
      free |> Enum.sort_by(fn {s, n} -> {-n, inspect(s)} end) |> Enum.map(&elem(&1, 0))

    index = free_symbols |> Enum.with_index() |> Map.new()

    # The text as {:free, i} / {:fixed, letter}.
    text =
      Enum.map(symbols, fn
        :gap ->
          :gap

        s ->
          case fixed do
            %{^s => letter} -> {:fixed, letter}
            _ -> {:free, Map.fetch!(index, s)}
          end
      end)

    # Words are only scored when the text has word breaks.
    word_weight = if :gap in symbols, do: word_weight, else: 0.0

    cond do
      letter_count < 8 ->
        {:error, :too_short}

      free_symbols == [] ->
        {:ok, %{mapping: %{}, score: English.score_per_quadgram(letters(decode(text, {})))}}

      true ->
        available = Enum.to_list(0..25) -- Map.values(fixed)
        # One letter per symbol when there are enough letters.
        injective? = length(free_symbols) <= length(available)
        start = initial_key(length(free_symbols), available)

        {key, score} =
          Enum.reduce(1..restarts, {nil, :neg_infinity}, fn restart, best ->
            key = if restart == 1, do: start, else: shuffle_key(start, available, injective?)

            candidate =
              climb(text, key, available, injective?, iterations, temperature, word_weight)

            better(candidate, best)
          end)

        mapping =
          free_symbols
          |> Enum.with_index()
          |> Map.new(fn {s, i} -> {s, <<?A + elem(key, i)>>} end)

        quality = English.score_per_quadgram(letters(decode(text, key)))
        {:ok, %{mapping: mapping, score: quality, fitness: score}}
    end
  end

  defp better({_, score} = candidate, {_, best_score}) when best_score == :neg_infinity,
    do: if(score, do: candidate)

  defp better({_, score} = candidate, {_, best_score} = best),
    do: if(score > best_score, do: candidate, else: best)

  # Most frequent symbols first get the most frequent English letters.
  defp initial_key(count, available) do
    order = Enum.filter(@english_order, &(&1 in available))

    0..(count - 1)
    |> Enum.map(fn i -> Enum.at(order, rem(i, length(order))) end)
    |> List.to_tuple()
  end

  defp shuffle_key(start, available, true) do
    letters = Enum.shuffle(available) |> Enum.take(tuple_size(start))
    List.to_tuple(letters)
  end

  defp shuffle_key(start, available, false) do
    0..(tuple_size(start) - 1) |> Enum.map(fn _ -> Enum.random(available) end) |> List.to_tuple()
  end

  # Simulated annealing: a worse assignment is sometimes accepted, less and
  # less often (the temperature cools down to 0), to get out of dead ends.
  # Returns the best assignment met.
  defp climb(text, key, available, injective?, iterations, temperature, word_weight) do
    score = fitness(text, key, word_weight)

    {_, _, best} =
      Enum.reduce(1..iterations, {key, score, {key, score}}, fn step, {key, score, best} ->
        candidate = tweak(key, available, injective?)
        candidate_score = fitness(text, candidate, word_weight)
        t = temperature * (1 - step / iterations)

        accept? =
          candidate_score > score or
            (t > 0 and :rand.uniform() < :math.exp((candidate_score - score) / t))

        if accept? do
          best = if candidate_score > elem(best, 1), do: {candidate, candidate_score}, else: best
          {candidate, candidate_score, best}
        else
          {key, score, best}
        end
      end)

    best
  end

  # Swap the letters of two symbols, or give a symbol a letter no other
  # symbol uses (injective), or any letter (more symbols than letters).
  #
  # (Letting symbols share a letter when there are enough letters doesn't
  # work: the search then collapses many symbols onto E, T, S… which scores
  # well on quadgrams while being gibberish.)
  defp tweak(key, available, injective?) do
    i = :rand.uniform(tuple_size(key)) - 1

    if injective? do
      unused = available -- Tuple.to_list(key)

      if unused != [] and :rand.uniform(3) == 1 do
        put_elem(key, i, Enum.random(unused))
      else
        j = :rand.uniform(tuple_size(key)) - 1
        key |> put_elem(i, elem(key, j)) |> put_elem(j, elem(key, i))
      end
    else
      put_elem(key, i, Enum.random(available))
    end
  end

  # How English the decoded text looks: its letter quadgrams, plus its words
  # when there are word breaks.
  defp fitness(text, key, word_weight) do
    decoded = decode(text, key)
    quadgrams = English.score(letters(decoded))

    if word_weight > 0,
      do: quadgrams + word_weight * English.words_score(words(decoded)),
      else: quadgrams
  end

  defp decode(text, key) do
    Enum.map(text, fn
      {:fixed, letter} -> letter
      {:free, i} -> elem(key, i)
      :gap -> :gap
    end)
  end

  defp letters(decoded), do: Enum.reject(decoded, &(&1 == :gap))

  defp words(decoded) do
    decoded |> Enum.chunk_by(&(&1 == :gap)) |> Enum.reject(&(&1 == [:gap] or hd(&1) == :gap))
  end

  @doc """
  The reason to show for a solver result: how it was found, and how many of
  the decoded words are English (`decoded`: the text with the solution
  applied, words separated by spaces).
  """
  def explain(decoded) do
    words =
      decoded |> String.split(~r/[^A-Za-z]+/, trim: true) |> Enum.filter(&(String.length(&1) > 1))

    known = Enum.count(words, &English.word?/1)

    found =
      "Found by trying many letter assignments and keeping the one that reads most like English"

    case words do
      [] ->
        found <> "."

      _ ->
        found <>
          ": #{known} of #{length(words)} words are English words" <>
          if(known < length(words),
            do: "; the others may be names or codes, or letters to fix by hand.",
            else: "."
          )
    end
  end
end
