defmodule Subcipher.Steps.Ciphers.Vigenere do
  @moduledoc """
  Vigenère cipher: each letter was shifted forward by the matching letter of
  a repeating key (A = 0, B = 1…). Decoding shifts back. The key only
  advances on letters.
  """
  use Subcipher.Steps.Cipher

  @impl true
  def type, do: "vigenere"

  @impl true
  def name, do: "Vigenère cipher"

  @impl true
  def description,
    do: "Like a Caesar cipher, but the shift changes with every letter, following a repeated key."

  @impl true
  def osrs_usage,
    do: "Shattered Relics League ARG (runestone basalt clues), Demonic Pacts League reveal."

  @impl true
  def fields do
    [
      %{
        name: :key,
        type: :string,
        label: "Key",
        default: "",
        help: "Letters only; spaces are ignored."
      }
    ]
  end

  @impl true
  def validate(changeset) do
    validate_format(changeset, :key, ~r/^[A-Za-z ]*$/, message: "letters only")
  end

  @impl true
  def decode(text, %{key: key}) do
    case for(<<c <- String.upcase(key || "")>>, c in ?A..?Z, do: c - ?A) do
      [] ->
        text

      shifts ->
        shifts = List.to_tuple(shifts)

        {decoded, _} =
          text
          |> String.graphemes()
          |> Enum.map_reduce(0, fn char, i ->
            if char =~ ~r/^[A-Za-z]$/ do
              shift = elem(shifts, rem(i, tuple_size(shifts)))
              {Alphabet.map_letters(char, &rem(&1 - shift + 26, 26)), i + 1}
            else
              {char, i}
            end
          end)

        Enum.join(decoded)
    end
  end

  # Below this many letters, the statistics below mean nothing.
  @min_letters 20
  @max_key_length 12

  @impl true
  def suggestions(input, _params) do
    letters = for <<c <- String.upcase(input)>>, c in ?A..?Z, do: c - ?A
    count = length(letters)

    if count < @min_letters do
      []
    else
      # Key lengths whose columns each still have a few letters.
      max_length = min(@max_key_length, div(count, 4))

      candidates =
        Map.new(1..max_length, fn length ->
          columns = columns(letters, length)
          {length, {columns, mean_ioc(columns)}}
        end)

      candidates
      # Multiples of the right key length look as English-like as the length
      # itself (and fit their columns even better, with fewer letters each):
      # keep the shortest length explaining the letter repetition.
      |> Enum.reject(fn {length, {_, ioc}} ->
        Enum.any?(1..(length - 1)//1, fn d ->
          rem(length, d) == 0 and elem(candidates[d], 1) >= 0.85 * ioc
        end)
      end)
      |> Enum.sort_by(fn {length, {_, ioc}} -> {-ioc, length} end)
      |> Enum.take(5)
      |> Enum.map(fn {length, {columns, ioc}} ->
        key = Enum.map_join(columns, &best_shift_letter/1)

        %{
          label: "Key #{key}",
          params: %{key: key},
          reason: reason(length, ioc, decode(input, %{key: key}))
        }
      end)
    end
  end

  # The letters at positions i, i + length, i + 2·length… for each i.
  defp columns(letters, length) do
    letters
    |> Enum.with_index()
    |> Enum.group_by(fn {_, i} -> rem(i, length) end, &elem(&1, 0))
    |> Enum.sort()
    |> Enum.map(&elem(&1, 1))
  end

  defp mean_ioc(columns) do
    columns
    |> Enum.map(fn column ->
      column |> Enum.map(&<<?A + &1>>) |> Enum.join() |> Alphabet.index_of_coincidence()
    end)
    |> then(&(Enum.sum(&1) / length(&1)))
  end

  # The key letter of a column: the Caesar shift making it most English-like.
  defp best_shift_letter(column) do
    shift =
      Enum.min_by(0..25, fn shift ->
        column
        |> Enum.map(&<<?A + rem(&1 - shift + 26, 26)>>)
        |> Enum.join()
        |> Alphabet.english_score()
      end)

    <<?A + shift>>
  end

  defp reason(length, ioc, output) do
    evidence =
      if ioc >= 0.055,
        do: "letters #{length} apart repeat like English does",
        else: "weak evidence, letters #{length} apart repeat only a little more than random ones"

    base =
      "Key length #{length}: #{evidence} " <>
        "(index of coincidence #{Float.round(ioc, 3)}; English ≈ 0.066, random ≈ 0.038), " <>
        "and each key letter is the shift making its letters most English-like"

    case Alphabet.words_hint(output) do
      nil -> base <> "."
      hint -> base <> "; the result " <> hint <> "."
    end
  end
end
