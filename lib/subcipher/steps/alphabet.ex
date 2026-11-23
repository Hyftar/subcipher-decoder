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
end
