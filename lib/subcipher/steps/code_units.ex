defmodule Subcipher.Steps.CodeUnits do
  @moduledoc """
  Helpers for text written as numbers in binary or hexadecimal: ASCII
  codes, UTF-8 bytes or Unicode code points (the ciphers
  `Subcipher.Steps.Ciphers.BinaryAscii`, `HexAscii`, `BinaryUnicode` and
  `HexUnicode`).

  The numbers are separated by spaces, commas or semicolons, or run
  together (then cut every `unit` digits: 8 bits or 2 hexadecimal digits a
  byte). Usual prefixes are accepted: `0b` in binary; `0x`, `\\x`, `U+`,
  `\\u` and `&#x…;` in hexadecimal. Lines are decoded separately; a line
  that isn't all numbers is left as it is. Characters that can't be decoded
  (codes out of range, invalid UTF-8, control characters) become "·".
  """

  alias Subcipher.Steps.Alphabet

  @doc """
  Decodes each line of `text` whose tokens are all numbers in `base`, with
  `fun` (receiving the line's tokens, prefixes stripped, and returning the
  decoded text, or `:error` to keep the line as it is).
  """
  def decode_lines(text, base, fun) do
    text
    |> String.split("\n")
    |> Enum.map_join("\n", fn line ->
      with {:ok, tokens} <- tokens(line, base),
           decoded when is_binary(decoded) <- fun.(tokens) do
        decoded
      else
        _ -> line
      end
    end)
  end

  @doc """
  The numbers of `line` in `base`, prefixes stripped: `{:ok, tokens}`, or
  `:error` when the line is empty or something isn't such a number.
  """
  def tokens(line, base) do
    tokens =
      line
      # Prefixes separate numbers too: \u2600\u0048.
      |> String.replace(prefixes(base), " \\1")
      |> String.split(~r/[\s,;]+/u, trim: true)
      |> Enum.map(&strip_prefix(&1, base))

    if tokens != [] and Enum.all?(tokens, &(&1 =~ digits(base))),
      do: {:ok, tokens},
      else: :error
  end

  defp prefixes(2), do: ~r/(0[bB])/
  defp prefixes(16), do: ~r/(0[xX]|\\[xXuU]|[uU]\+|&#[xX])/

  defp digits(2), do: ~r/^[01]+$/
  defp digits(16), do: ~r/^[0-9A-Fa-f]+$/

  defp strip_prefix(token, 2), do: String.replace(token, ~r/^0[bB]/, "")

  defp strip_prefix(token, 16),
    do:
      token
      |> String.replace(~r/^(0[xX]|\\[xXuU]|[uU]\+|&#[xX])/, "")
      |> String.trim_trailing(";")

  @doc "Whether a token of `line` has a Unicode prefix (`U+`, `\\u`)."
  def code_point_prefix?(text), do: text =~ ~r/(^|[\s,;])([uU]\+|\\[uU])[0-9A-Fa-f]/

  @doc """
  The values of `tokens` in `base`: each token is one value, unless it is
  longer than `unit` digits (numbers run together): then it is cut every
  `unit` digits, `:error` when it doesn't divide. With `unit` nil, every
  token is one value.
  """
  def values(tokens, base, unit) do
    tokens
    |> Enum.reduce_while([], fn token, acc ->
      size = byte_size(token)

      cond do
        unit == nil or size <= unit ->
          {:cont, [String.to_integer(token, base) | acc]}

        rem(size, unit) == 0 ->
          chunks = for <<chunk::binary-size(^unit) <- token>>, do: String.to_integer(chunk, base)
          {:cont, Enum.reverse(chunks, acc)}

        true ->
          {:halt, :error}
      end
    end)
    |> case do
      :error -> :error
      values -> Enum.reverse(values)
    end
  end

  @doc "ASCII codes as text: codes above 127 and control characters become \"·\"."
  def ascii(values) do
    values
    |> Enum.map_join(fn value -> if value in 0..127, do: <<value>>, else: Alphabet.unknown() end)
    |> clean()
  end

  @doc "UTF-8 bytes as text (`:error` if a value isn't a byte); invalid sequences become \"·\"."
  def utf8(values) do
    if Enum.all?(values, &(&1 in 0..255)) do
      values |> :erlang.list_to_binary() |> String.replace_invalid(Alphabet.unknown()) |> clean()
    else
      :error
    end
  end

  @doc "Unicode code points as text; invalid ones become \"·\"."
  def code_points(values) do
    values
    |> Enum.map_join(fn value ->
      if value in 0..0x10FFFF and value not in 0xD800..0xDFFF,
        do: <<value::utf8>>,
        else: Alphabet.unknown()
    end)
    |> clean()
  end

  # Control characters (but line breaks and tabs) are no text.
  defp clean(text),
    do: String.replace(text, ~r/[\x00-\x08\x0B\x0C\x0E-\x1F\x7F]/u, Alphabet.unknown())

  @doc "`value` in `base`, at least `digits` digits (hexadecimal in capitals)."
  def format(value, base, digits),
    do: value |> Integer.to_string(base) |> String.pad_leading(digits, "0")

  @doc """
  How well `output` decoded `input`, for comparing settings: decoding
  everything first (`clean_decode?/2`: a reading leaving lines as they are
  decodes nothing), then fewest undecodable characters, then how English it
  reads.
  """
  def rank(input, output) do
    unknown = output |> String.graphemes() |> Enum.count(&(&1 == Alphabet.unknown()))
    english = Subcipher.English.score_per_quadgram(Subcipher.English.letters(output)) || -99.0
    {clean_decode?(input, output), output != input, -unknown, english}
  end

  @doc """
  Whether `output`, decoded from `input`, decodes everything: it changed,
  has some text and no undecodable character.
  """
  def clean_decode?(input, output) do
    output != input and String.trim(output) != "" and
      not String.contains?(output, Alphabet.unknown())
  end

  @doc "Whether every non-blank line of `text` is numbers in `base`."
  def all_numbers?(text, base) do
    lines = text |> String.split("\n") |> Enum.reject(&(String.trim(&1) == ""))
    lines != [] and Enum.all?(lines, &match?({:ok, _}, tokens(&1, base)))
  end
end
