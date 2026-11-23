defmodule Subcipher.Repo.Migrations.CreateAlgorithms do
  use Ecto.Migration

  # A puzzle's decoding steps, frozen, to encode and decode any text. For a
  # pictures puzzle, the symbol key (a sample glyph per letter) and copies of
  # the pictures those glyphs are cropped from.
  def change do
    create table(:algorithms) do
      add :title, :string, null: false
      add :input_kind, :string, null: false
      add :steps, {:array, :map}, null: false, default: []
      add :symbol_key, {:array, :map}, null: false, default: []
      add :images, {:array, :map}, null: false, default: []
      add :source_puzzle_id, references(:puzzles, on_delete: :nilify_all)

      timestamps(type: :utc_datetime)
    end
  end
end
