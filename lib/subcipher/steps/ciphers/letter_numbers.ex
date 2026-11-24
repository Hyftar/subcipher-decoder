defmodule Subcipher.Steps.Ciphers.LetterNumbers do
  @moduledoc """
  Letter numbers (A1Z26): each letter was replaced by its position in the
  alphabet. Numbers are separated by spaces, commas, dots or dashes; words by
  "/", "|" or several spaces. Lines whose words aren't all numbers are left
  as they are; numbers out of range become "·".
  """
  use Subcipher.Steps.Cipher

  @impl true
  def type, do: "letter_numbers"

  @impl true
  def name, do: "Letter numbers (A1Z26)"

  @impl true
  def description, do: "Each letter was replaced by its number in the alphabet: A = 1 … Z = 26."

  @impl true
  def osrs_usage,
    do:
      "Shattered Relics League ARG, Crack the Clue III, Beneath Cursed Sands (chest code), 2023 Easter event."

  @impl true
  def fields do
    [
      %{
        name: :first,
        type: :select,
        label: "A is",
        default: "1",
        options: [{"1 (A1Z26)", "1"}, {"0 (A0Z25)", "0"}]
      }
    ]
  end

  @impl true
  # Letters become numbers separated by spaces, words separated by " | ";
  # anything but letters is left out.
  def encode(text, %{first: first}) do
    first = String.to_integer(first)

    text
    |> String.split("\n")
    |> Enum.map_join("\n", fn line ->
      line
      |> String.upcase()
      |> String.split(~r/[^A-Z]+/, trim: true)
      |> Enum.map_join(" | ", fn word ->
        for(<<c <- word>>, do: Integer.to_string(c - ?A + first)) |> Enum.join(" ")
      end)
    end)
  end

  @impl true
  def decode(text, %{first: first}) do
    first = String.to_integer(first)
    text |> String.split("\n") |> Enum.map_join("\n", &decode_line(&1, first))
  end

  defp decode_line(line, first) do
    words = line |> String.trim() |> String.split(~r/\s*[\/|]\s*|\s{2,}/u, trim: true)

    if words != [] and Enum.all?(words, &(&1 =~ ~r/^\d+([\s,.\-]+\d+)*$/)),
      do: Enum.map_join(words, " ", &decode_word(&1, first)),
      else: line
  end

  defp decode_word(word, first) do
    word
    |> String.split(~r/[\s,.\-]+/, trim: true)
    |> Enum.map_join(fn number ->
      index = String.to_integer(number) - first
      if index in 0..25, do: <<?A + index>>, else: Alphabet.unknown()
    end)
  end

  # Whether A is 1 or 0 shows in the numbers themselves.
  @impl true
  def suggestions(input, _params) do
    numbers = Regex.scan(~r/\d+/, input) |> List.flatten() |> Enum.map(&String.to_integer/1)

    if numbers == [] do
      []
    else
      zero? = 0 in numbers
      twenty_six? = 26 in numbers
      out_of_range = Enum.count(numbers, &(&1 > 26))

      one = %{
        label: "A = 1 (A1Z26)",
        params: %{first: "1"},
        reason:
          cond do
            zero? -> "Unlikely: the text has a 0, which A1Z26 can't encode."
            twenty_six? -> "The text has a 26, which only exists when A = 1 (Z = 26)."
            true -> "The usual convention: all numbers are between 1 and 26."
          end <> out_of_range_note(out_of_range)
      }

      zero = %{
        label: "A = 0",
        params: %{first: "0"},
        reason:
          cond do
            zero? -> "The text has a 0, which only exists when A = 0."
            twenty_six? -> "Unlikely: the text has a 26, which doesn't exist when A = 0 (Z = 25)."
            true -> "The other convention: every letter one place later than with A = 1."
          end <> out_of_range_note(out_of_range)
      }

      if zero? and not twenty_six?, do: [zero, one], else: [one, zero]
    end
  end

  # Only numbers (and separators), all of them letters with A = 0 or 1.
  @impl true
  def recognize(input) do
    numbers = Regex.scan(~r/\d+/, input) |> List.flatten() |> Enum.map(&String.to_integer/1)
    only_numbers? = String.replace(input, ~r/[\d\s,.\-\/|]+/u, "") == ""

    cond do
      numbers == [] or not only_numbers? ->
        nil

      Enum.all?(numbers, &(&1 in 1..26)) ->
        "The text has only numbers from 1 to 26: positions of letters in the alphabet."

      Enum.all?(numbers, &(&1 in 0..25)) ->
        "The text has only numbers from 0 to 25: positions of letters in the alphabet (A = 0)."

      true ->
        nil
    end
  end

  defp out_of_range_note(0), do: ""
  defp out_of_range_note(n), do: " #{n} number(s) are above 26: maybe not letter numbers."
end
