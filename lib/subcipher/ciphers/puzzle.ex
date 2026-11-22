defmodule Subcipher.Ciphers.Puzzle do
  use Ecto.Schema
  import Ecto.Changeset

  schema "puzzles" do
    field :title, :string
    field :threshold, :float

    has_many :images, Subcipher.Ciphers.Image
    has_many :symbols, Subcipher.Ciphers.Symbol
    has_many :glyphs, Subcipher.Ciphers.Glyph

    timestamps(type: :utc_datetime)
  end

  def changeset(puzzle, attrs) do
    puzzle
    |> cast(attrs, [:title, :threshold])
    |> update_change(:title, &String.trim/1)
    |> validate_required([:title, :threshold])
    |> validate_length(:title, max: 120)
  end

  def title_changeset(puzzle, attrs) do
    puzzle
    |> cast(attrs, [:title])
    |> update_change(:title, &String.trim/1)
    |> validate_required([:title])
    |> validate_length(:title, max: 120)
  end
end
