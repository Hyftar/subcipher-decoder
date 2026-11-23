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
