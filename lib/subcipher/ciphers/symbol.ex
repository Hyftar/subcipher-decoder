defmodule Subcipher.Ciphers.Symbol do
  use Ecto.Schema
  import Ecto.Changeset

  schema "symbols" do
    # The plain-text substitution chosen by the user (nil = still unknown).
    field :letter, :string
    # Noise / decoration the user chose to hide from the text.
    field :ignored, :boolean, default: false

    belongs_to :puzzle, Subcipher.Ciphers.Puzzle
    has_many :glyphs, Subcipher.Ciphers.Glyph

    timestamps(type: :utc_datetime)
  end

  def changeset(symbol, attrs) do
    symbol
    |> cast(attrs, [:letter, :ignored])
    |> update_change(:letter, &normalize_letter/1)
    |> validate_length(:letter, max: 3)
  end

  defp normalize_letter(nil), do: nil

  defp normalize_letter(letter) do
    case letter |> String.trim() |> String.upcase() do
      "" -> nil
      l -> l
    end
  end
end
