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
  def decode(text, %{shift: shift}) do
    Alphabet.map_letters(text, &rem(&1 - shift + 26, 26))
  end

  @impl true
  def summary(%{shift: shift}), do: "A → #{<<?A + shift>>}, B → #{<<?A + rem(shift + 1, 26)>>}…"

  # Only 26 keys: try them all and rank them by how English the result looks.
  @impl true
  def candidates(input, _params) do
    0..25
    |> Enum.map(fn shift ->
      output = decode(input, %{shift: shift})
      {Alphabet.english_score(output), shift, output}
    end)
    |> Enum.sort()
    |> Enum.map(fn {_score, shift, output} ->
      %{label: "Shift #{shift}", params: %{shift: shift}, preview: output}
    end)
  end
end
