defmodule Subcipher.KeySpace do
  @moduledoc """
  Sizes of key spaces, as log10 of the number of possible keys.

  A cipher with more possible keys can make more texts read like English
  by chance: guessing (`Subcipher.Guesser`) and the solvers charge each
  result the size of the key space it was picked from, so a big key has to
  fit much better to win (the minimum description length principle). A
  Caesar shift costs log10(26) ≈ 1.4, a dictionary word ≈ 4.3, a free
  mixed alphabet up to log10(26!) ≈ 26.6.
  """

  alias Subcipher.English

  @letter :math.log10(26)

  @doc "One of `n` choices."
  def choices(n) when n >= 1, do: :math.log10(n)

  @doc "A free sequence of `n` letters."
  def letters(n), do: n * @letter

  @doc """
  A key word (a string): one of the dictionary's words when it is one, else
  a free sequence of its letters.
  """
  def word(word) do
    letters = English.letters(word)

    cond do
      letters == [] -> 0.0
      length(letters) >= 2 and English.word?(word) -> choices(English.dictionary_size())
      true -> letters(length(letters))
    end
  end

  @doc """
  An assignment of distinct letters to `m` symbols (a substitution
  alphabet, only the letters used counting); symbols beyond 26 share
  letters.
  """
  def permutation(m) do
    distinct = min(m, 26)
    Enum.reduce(0..(distinct - 1)//1, 0.0, &(&2 + :math.log10(26 - &1))) + letters(m - distinct)
  end
end
