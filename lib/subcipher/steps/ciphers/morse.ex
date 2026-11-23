defmodule Subcipher.Steps.Ciphers.Morse do
  @moduledoc """
  International Morse code. Letters are separated by a space; words by "/",
  "|" or several spaces; lines are decoded separately. Accepts "." "•" "∙"
  for dots and "-" "–" "—" "−" "_" for dashes. Words that aren't Morse are
  left as they are; unknown codes become "·".
  """
  use Subcipher.Steps.Cipher

  @codes %{
    ".-" => "A",
    "-..." => "B",
    "-.-." => "C",
    "-.." => "D",
    "." => "E",
    "..-." => "F",
    "--." => "G",
    "...." => "H",
    ".." => "I",
    ".---" => "J",
    "-.-" => "K",
    ".-.." => "L",
    "--" => "M",
    "-." => "N",
    "---" => "O",
    ".--." => "P",
    "--.-" => "Q",
    ".-." => "R",
    "..." => "S",
    "-" => "T",
    "..-" => "U",
    "...-" => "V",
    ".--" => "W",
    "-..-" => "X",
    "-.--" => "Y",
    "--.." => "Z",
    "-----" => "0",
    ".----" => "1",
    "..---" => "2",
    "...--" => "3",
    "....-" => "4",
    "....." => "5",
    "-...." => "6",
    "--..." => "7",
    "---.." => "8",
    "----." => "9",
    ".-.-.-" => ".",
    "--..--" => ",",
    "..--.." => "?",
    ".----." => "'",
    "-.-.--" => "!",
    "-..-." => "/",
    "-.--." => "(",
    "-.--.-" => ")",
    ".-..." => "&",
    "---..." => ":",
    "-.-.-." => ";",
    "-...-" => "=",
    ".-.-." => "+",
    "-....-" => "-",
    ".-..-." => "\"",
    ".--.-." => "@"
  }

  @impl true
  def type, do: "morse"

  @impl true
  def name, do: "Morse code"

  @impl true
  def description,
    do: "Dots and dashes; letters separated by a space, words by “/”, “|” or several spaces."

  @impl true
  def osrs_usage,
    do: "Easter eggs all over Gielinor: bank booths, gravestones, Alliance records, contracts…"

  @impl true
  def fields, do: []

  @impl true
  # Letters separated by a space, words by " / ". Characters without a Morse
  # code become the error signal (8 dots), decoded as unknown.
  def encode(text, _params) do
    letters = Map.new(@codes, fn {code, char} -> {char, code} end)

    text
    |> String.split("\n")
    |> Enum.map_join("\n", fn line ->
      line
      |> String.split(~r/\s+/u, trim: true)
      |> Enum.map_join(" / ", fn word ->
        word
        |> String.upcase()
        |> String.graphemes()
        |> Enum.map_join(" ", &Map.get(letters, &1, "........"))
      end)
    end)
  end

  @impl true
  def decode(text, _params) do
    text |> String.split("\n") |> Enum.map_join("\n", &decode_line/1)
  end

  defp decode_line(line) do
    words = line |> String.trim() |> String.split(~r/\s*[\/|]\s*|\s{2,}/u, trim: true)

    if words != [] and Enum.all?(words, &morse?/1),
      do: Enum.map_join(words, " ", &decode_word/1),
      else: line
  end

  defp normalize(token) do
    token
    |> String.replace(~r/[•∙]/u, ".")
    |> String.replace(~r/[–—−_]/u, "-")
  end

  defp morse?(word), do: normalize(word) =~ ~r/^[.\- ]+$/

  defp decode_word(word) do
    word
    |> normalize()
    |> String.split(" ", trim: true)
    |> Enum.map_join(&Map.get(@codes, &1, Alphabet.unknown()))
  end
end
