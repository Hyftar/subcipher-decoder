defmodule Subcipher.Ciphers.Puzzle do
  use Ecto.Schema
  import Ecto.Changeset

  schema "puzzles" do
    field :title, :string
    field :image_path, :string
    field :image_width, :integer
    field :image_height, :integer
    field :threshold, :float

    has_many :symbols, Subcipher.Ciphers.Symbol
    has_many :glyphs, Subcipher.Ciphers.Glyph

    timestamps(type: :utc_datetime)
  end

  def changeset(puzzle, attrs) do
    puzzle
    |> cast(attrs, [:title, :image_path, :image_width, :image_height, :threshold])
    |> update_change(:title, &String.trim/1)
    |> validate_required([:title, :image_path, :image_width, :image_height, :threshold])
    |> validate_length(:title, max: 120)
    |> validate_number(:image_width, greater_than: 0)
    |> validate_number(:image_height, greater_than: 0)
  end

  def title_changeset(puzzle, attrs) do
    puzzle
    |> cast(attrs, [:title])
    |> update_change(:title, &String.trim/1)
    |> validate_required([:title])
    |> validate_length(:title, max: 120)
  end
end
