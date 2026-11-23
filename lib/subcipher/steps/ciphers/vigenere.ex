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
end
