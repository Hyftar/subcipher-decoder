defmodule Subcipher.Ciphers.Image do
  @moduledoc "One picture of a puzzle's cipher text."
  use Ecto.Schema

  schema "images" do
    # Public path, e.g. "/uploads/<uuid>.png"
    field :path, :string
    field :width, :integer
    field :height, :integer
    # Reading order of the pictures within the puzzle.
    field :position, :integer

    belongs_to :puzzle, Subcipher.Ciphers.Puzzle
    has_many :glyphs, Subcipher.Ciphers.Glyph

    timestamps(type: :utc_datetime)
  end
end
