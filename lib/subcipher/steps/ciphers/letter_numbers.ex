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
end
