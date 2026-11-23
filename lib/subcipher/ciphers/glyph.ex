defmodule Subcipher.Ciphers.Glyph do
  @moduledoc "One occurrence of a symbol in the picture."
  use Ecto.Schema

  schema "glyphs" do
    # Reading order within its image.
    field :position, :integer
    field :line, :integer
    field :space_before, :boolean, default: false
    field :x, :integer
    field :y, :integer
    field :w, :integer
    field :h, :integer
    # 16x16 ink coverage grid, used to (re)cluster symbols.
    field :features, :binary, redact: true
    # The box found by detection, kept when the user trims the glyph (so the
    # crop can be reset): %{"x", "y", "w", "h"}; nil = never trimmed.
    field :detected_box, :map

    belongs_to :puzzle, Subcipher.Ciphers.Puzzle
    belongs_to :image, Subcipher.Ciphers.Image
    belongs_to :symbol, Subcipher.Ciphers.Symbol
  end
end
