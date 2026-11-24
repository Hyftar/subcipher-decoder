defmodule Subcipher.Solvers.KeywordSearch do
  @moduledoc """
  Finds the keyword of a keyword substitution
  (`Subcipher.Steps.Ciphers.KeywordSubstitution`): the one making the text
  read most like English (`Subcipher.English.text_score/1`).

  1. Every dictionary word (and the `:known` keywords) is tried.
  2. Simulated annealing over keywords (strings of distinct letters):
     insert, delete, swap or change a letter, keeping changes that read
     better (early on, some that read slightly worse). It starts from the
     best dictionary words, from the keyword read off the alphabet the
     general solver finds (`Subcipher.Solver`, long texts), and from
     random keywords.
  3. Keywords giving the same text (they differ only in letters the text
     doesn't use) are equivalent: a dictionary word among them is preferred.

  Seeded, so the same text gives the same keyword.
  """

  alias Subcipher.English

  @max_length 12
  @seeds 5
  @random_starts 20
  @iterations 2000
  @temperature 2.0
  # The general solver is reliable from about this many letters.
  @solver_letters 60

  @doc """
  The best keyword (a string) for the cipher text `words` (lists of cipher
  letters 0..25) and its score. Options: `:known` (extra keywords to try),
  `:starts` (keywords to start the search from too, e.g. the current one),
  `:seed`.
  """
  def search(words, opts \\ []) do
    :rand.seed(:exsss, {Keyword.get(opts, :seed, 1), 17, 29})

    candidates =
      Enum.map(Keyword.get(opts, :known, []), &English.letters/1) ++
        English.dictionary(2, 15)

    swept =
      candidates
      |> Enum.map(&{&1, score(words, &1)})
      |> Enum.sort_by(&elem(&1, 1), :desc)

    seeds = Enum.take(swept, @seeds) |> Enum.map(&elem(&1, 0))

    given =
      opts |> Keyword.get(:starts, []) |> Enum.map(&English.letters/1) |> Enum.reject(&(&1 == []))

    starts = given ++ seeds ++ solver_seed(words) ++ random_keywords(@random_starts)

    {best, best_score} =
      starts
      |> Enum.map(&anneal(words, &1))
      |> Enum.max_by(&elem(&1, 1))

    # A dictionary word giving the same text (the same score) reads better.
    keyword =
      case Enum.find(swept, fn {_, s} -> s == best_score end) do
        {word, _} -> word
        nil -> best
      end

    {letters_to_string(keyword), best_score}
  end

  @doc "The score of decoding `words` with `keyword` (a list of letters)."
  def score(words, keyword) do
    inverse = inverse(keyword)
    words |> Enum.map(fn word -> Enum.map(word, &elem(inverse, &1)) end) |> English.text_score()
  end

  # Cipher letter -> plain letter, for the alphabet of `keyword`: the
  # keyword's distinct letters, then the rest in order.
  defp inverse(keyword) do
    keyword = Enum.uniq(keyword)
    alphabet = keyword ++ (Enum.to_list(0..25) -- keyword)

    alphabet
    |> Enum.with_index()
    |> Enum.sort()
    |> Enum.map(&elem(&1, 1))
    |> List.to_tuple()
  end

  defp letters_to_string(keyword), do: for(l <- keyword, into: "", do: <<?A + l>>)

  defp anneal(words, start) do
    start =
      case start |> Enum.uniq() |> Enum.take(@max_length) do
        [] -> [random_letter()]
        start -> start
      end

    {_, _, best, best_score} =
      Enum.reduce(1..@iterations, {start, score(words, start), start, score(words, start)}, fn
        i, {current, current_score, best, best_score} ->
          candidate = mutate(current)
          candidate_score = score(words, candidate)
          temperature = max(@temperature * (1 - i / @iterations), 0.01)

          {current, current_score} =
            if candidate_score >= current_score or
                 :rand.uniform() < :math.exp((candidate_score - current_score) / temperature),
               do: {candidate, candidate_score},
               else: {current, current_score}

          if current_score > best_score,
            do: {current, current_score, current, current_score},
            else: {current, current_score, best, best_score}
      end)

    {best, best_score}
  end

  defp mutate(keyword) do
    n = length(keyword)

    mutated =
      case :rand.uniform(5) do
        1 when n < @max_length ->
          List.insert_at(keyword, :rand.uniform(n + 1) - 1, random_letter())

        2 when n > 1 ->
          List.delete_at(keyword, :rand.uniform(n) - 1)

        3 when n > 1 ->
          i = :rand.uniform(n) - 1
          j = :rand.uniform(n) - 1

          keyword
          |> List.replace_at(i, Enum.at(keyword, j))
          |> List.replace_at(j, Enum.at(keyword, i))

        _ ->
          List.replace_at(keyword, :rand.uniform(n) - 1, random_letter())
      end

    case Enum.uniq(mutated) do
      [] -> [random_letter()]
      keyword -> keyword
    end
  end

  defp random_letter, do: :rand.uniform(26) - 1

  defp random_keywords(count) do
    for _ <- 1..count//1, do: Enum.uniq(for(_ <- 1..(2 + :rand.uniform(8)), do: random_letter()))
  end

  # On long texts, the general solver recovers the alphabet; a keyword
  # alphabet is the keyword then the other letters in order: the keyword
  # is what comes before that ordered run.
  defp solver_seed(words) do
    if length(List.flatten(words)) < @solver_letters do
      []
    else
      symbols =
        words |> Enum.map(fn word -> Enum.map(word, &<<?A + &1>>) end) |> Enum.intersperse([:gap])

      case Subcipher.Solver.solve(List.flatten(symbols)) do
        {:ok, %{mapping: mapping}} -> [keyword_from_mapping(mapping)]
        _ -> []
      end
    end
  end

  @doc """
  The keyword of a substitution alphabet (`%{"cipher letter" => "plain
  letter"}`): the cipher letters of the plain letters before the longest
  ordered run of the others. Letters missing from the mapping are skipped.
  """
  def keyword_from_mapping(mapping) do
    by_plain = Map.new(mapping, fn {<<c>>, <<p>>} -> {p - ?A, c - ?A} end)
    alphabet = for plain <- 0..25, do: Map.get(by_plain, plain)

    start =
      Enum.find(0..25, fn k ->
        known = alphabet |> Enum.drop(k) |> Enum.reject(&is_nil/1)
        known == Enum.sort(known) and known == Enum.uniq(known)
      end)

    alphabet |> Enum.take(start) |> Enum.reject(&is_nil/1) |> Enum.uniq()
  end
end
