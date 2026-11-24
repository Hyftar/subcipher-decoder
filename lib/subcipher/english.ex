defmodule Subcipher.English do
  @moduledoc """
  How English a sequence of letters looks, from the frequencies of 4-letter
  sequences ("quadgrams") in English prose (`priv/english/quadgrams.txt`,
  built by `scripts/build_quadgrams.exs`).

  Letters are indexes 0..25 (A..Z). Spaces and punctuation are not scored:
  the statistics come from letters only.
  """

  @size 26 * 26 * 26 * 26

  @doc """
  Sum of the log10 probabilities of the quadgrams of `letters` (higher is
  more English-like). Quadgrams never seen in English get a small floor
  probability.
  """
  def score(letters) when is_list(letters) do
    table = table()

    {total, _, _} =
      Enum.reduce(letters, {0.0, 0, 0}, fn letter, {total, index, seen} ->
        index = rem(index * 26 + letter, @size)

        if seen >= 3,
          do: {total + lookup(table, index), index, seen + 1},
          else: {total, index, seen + 1}
      end)

    total
  end

  @doc """
  Log10 probability of the quadgram `a b c d` (letters 0..25), for scoring
  a text letter by letter.
  """
  def quadgram(a, b, c, d), do: lookup(table(), ((a * 26 + b) * 26 + c) * 26 + d)

  @doc "Average log10 probability per quadgram: comparable across lengths."
  def score_per_quadgram(letters) do
    case length(letters) - 3 do
      n when n > 0 -> score(letters) / n
      _ -> nil
    end
  end

  @doc """
  How English a list of words looks (each word a list of letters 0..25):
  frequent dictionary words score well (log10 of their frequency), unknown
  words get a penalty growing with their length (a short unknown word may
  be a name or a code, a long one is unlikely).
  """
  def words_score(words) do
    {table, unknown} = word_table()

    Enum.reduce(words, 0.0, fn letters, total ->
      case table do
        %{^letters => score} -> total + score
        _ -> total + unknown - 0.5 * length(letters)
      end
    end)
  end

  @doc """
  Log10 frequency of a word (a list of letters 0..25) in English, or the
  frequency given to words that aren't in the dictionary, plus
  `unknown_per_letter` for each of their letters (`words_score/1` uses
  -0.5).
  """
  def word_score(letters, unknown_per_letter) do
    {table, _} = word_table()

    case table do
      %{^letters => score} -> score
      _ -> unknown_word_score(length(letters), unknown_per_letter)
    end
  end

  @doc "The score `word_score/2` gives a word of `length` letters not in the dictionary."
  def unknown_word_score(length, unknown_per_letter) do
    {_, unknown} = word_table()
    unknown + unknown_per_letter * length
  end

  @doc """
  How English a text reads, as a list of words (each a list of letters
  0..25): its quadgrams (`score/1`, across words) plus its dictionary words
  (`words_score/1`). The fitness the solvers maximise.
  """
  def text_score(words), do: score(List.flatten(words)) + words_score(words)

  @doc "The words of `text`: its runs of letters, each a list of letters 0..25."
  def words(text) do
    text |> String.upcase() |> String.split(~r/[^A-Z]+/, trim: true) |> Enum.map(&letters/1)
  end

  @doc """
  The dictionary words (lists of letters 0..25) of `min`..`max` letters,
  most frequent first.
  """
  def dictionary(min \\ 1, max \\ 100) do
    sorted =
      case :persistent_term.get({__MODULE__, :dictionary}, nil) do
        nil ->
          {table, _} = word_table()
          sorted = table |> Enum.sort_by(&elem(&1, 1), :desc) |> Enum.map(&elem(&1, 0))
          :persistent_term.put({__MODULE__, :dictionary}, sorted)
          sorted

        sorted ->
          sorted
      end

    Enum.filter(sorted, &(length(&1) in min..max))
  end

  @doc "Number of words in the dictionary."
  def dictionary_size do
    {table, _} = word_table()
    map_size(table)
  end

  @doc "Whether `word` (a string) is in the dictionary."
  def word?(word) do
    {table, _} = word_table()
    letters = for <<c <- String.upcase(word)>>, c in ?A..?Z, do: c - ?A
    letters != [] and Map.has_key?(table, letters)
  end

  defp word_table do
    case :persistent_term.get({__MODULE__, :words}, nil) do
      nil ->
        [total | lines] =
          :subcipher
          |> Application.app_dir("priv/english/words.txt")
          |> File.read!()
          |> String.split("\n", trim: true)

        total = String.to_integer(total)

        table =
          Map.new(lines, fn line ->
            [word, count] = String.split(line, " ")
            letters = for <<c <- word>>, do: c - ?A
            {letters, :math.log10(String.to_integer(count) / total)}
          end)

        words = {table, :math.log10(0.5 / total)}
        :persistent_term.put({__MODULE__, :words}, words)
        words

      words ->
        words
    end
  end

  @doc "Letters (0..25) of `text`, ignoring everything else."
  def letters(text), do: for(<<c <- String.upcase(text)>>, c in ?A..?Z, do: c - ?A)

  defp lookup(table, index) do
    offset = index * 4
    <<_::binary-size(^offset), value::float-32-native, _::binary>> = table
    value
  end

  # One float per possible quadgram, built once and kept in persistent_term.
  defp table do
    case :persistent_term.get({__MODULE__, :table}, nil) do
      nil ->
        table = build_table()
        :persistent_term.put({__MODULE__, :table}, table)
        table

      table ->
        table
    end
  end

  defp build_table do
    [total | lines] =
      :subcipher
      |> Application.app_dir("priv/english/quadgrams.txt")
      |> File.read!()
      |> String.split("\n", trim: true)

    total = String.to_integer(total)
    floor = :math.log10(0.01 / total)

    known =
      Map.new(lines, fn line ->
        [quad, count] = String.split(line, " ")
        <<a, b, c, d>> = quad
        index = (((a - ?A) * 26 + (b - ?A)) * 26 + (c - ?A)) * 26 + (d - ?A)
        {index, :math.log10(String.to_integer(count) / total)}
      end)

    for index <- 0..(@size - 1), into: <<>> do
      <<Map.get(known, index, floor)::float-32-native>>
    end
  end
end
