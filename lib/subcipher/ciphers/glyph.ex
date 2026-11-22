defmodule Subcipher.Ciphers.Glyph do
  @moduledoc "One occurrence of a symbol in the picture."
  use Ecto.Schema

  schema "glyphs" do
    field :position, :integer
    field :line, :integer
    field :space_before, :boolean, default: false
    field :x, :integer
    field :y, :integer
    field :w, :integer
    field :h, :integer
    # 16x16 ink coverage grid, used to (re)cluster symbols.
    field :features, :binary, redact: true

    belongs_to :puzzle, Subcipher.Ciphers.Puzzle
    belongs_to :symbol, Subcipher.Ciphers.Symbol
  end
end
