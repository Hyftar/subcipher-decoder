defmodule Subcipher.Steps.Ciphers.Caesar do
  @moduledoc "Caesar cipher: every letter was shifted forward by the same amount."
  use Subcipher.Steps.Cipher

  @impl true
  def type, do: "caesar"

  @impl true
  def osrs_usage,
    do:
      "Treasure Trails cipher clues (NPC names), the Venom-riddled note (ROT13), Demonic Pacts League reveal."

  @impl true
  def name, do: "Caesar cipher"

  @impl true
  def description,
    do:
      "Each letter was shifted forward in the alphabet by the same amount (ROT13 is a shift of 13)."

  @impl true
  def fields do
    [
      %{
        name: :shift,
        type: :integer,
        label: "Shift",
        default: 3,
        min: 0,
        max: 25,
        help: "How far letters were shifted when encrypting (A → D is 3)."
      }
    ]
  end

  @impl true
  def validate(changeset) do
    validate_number(changeset, :shift, greater_than_or_equal_to: 0, less_than_or_equal_to: 25)
  end

  @impl true
  def encode(text, %{shift: shift}) do
    Alphabet.map_letters(text, &rem(&1 + shift, 26))
  end

  @impl true
  def decode(text, %{shift: shift}) do
    Alphabet.map_letters(text, &rem(&1 - shift + 26, 26))
  end

  @impl true
  def summary(%{shift: shift}), do: "A → #{<<?A + shift>>}, B → #{<<?A + rem(shift + 1, 26)>>}…"

  # Only 26 keys: try them all, keep the most English-looking results.
  @impl true
  def suggestions(input, _params) do
    if Alphabet.frequencies(input) == %{} do
      []
    else
      0..25
      |> Enum.map(fn shift -> {Alphabet.english_score(decode(input, %{shift: shift})), shift} end)
      |> Enum.sort()
      |> Enum.take(5)
      |> Enum.with_index(1)
      |> Enum.map(fn {{_score, shift}, rank} ->
        output = decode(input, %{shift: shift})

        %{
          label: if(shift == 13, do: "Shift 13 (ROT13)", else: "Shift #{shift}"),
          params: %{shift: shift},
          reason: reason(rank, output)
        }
      end)
    end
  end

  defp reason(rank, output) do
    closeness =
      case rank do
        1 -> "Of the 26 possible shifts, this one gives the letter frequencies closest to English"
        2 -> "The 2nd closest letter frequencies to English of the 26 shifts"
        3 -> "The 3rd closest letter frequencies to English of the 26 shifts"
        n -> "The #{n}th closest letter frequencies to English of the 26 shifts"
      end

    case Alphabet.words_hint(output) do
      nil -> closeness <> "."
      hint -> closeness <> "; the result " <> hint <> "."
    end
  end
end
