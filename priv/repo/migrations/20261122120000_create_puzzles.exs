defmodule Subcipher.Repo.Migrations.CreatePuzzles do
  use Ecto.Migration

  def change do
    create table(:puzzles) do
      add :title, :string, null: false
      add :image_path, :string, null: false
      add :image_width, :integer, null: false
      add :image_height, :integer, null: false
      add :threshold, :float, null: false

      timestamps(type: :utc_datetime)
    end

    create table(:symbols) do
      add :puzzle_id, references(:puzzles, on_delete: :delete_all), null: false
      add :letter, :string
      add :ignored, :boolean, null: false, default: false

      timestamps(type: :utc_datetime)
    end

    create index(:symbols, [:puzzle_id])

    create table(:glyphs) do
      add :puzzle_id, references(:puzzles, on_delete: :delete_all), null: false
      add :symbol_id, references(:symbols, on_delete: :restrict), null: false
      add :position, :integer, null: false
      add :line, :integer, null: false
      add :space_before, :boolean, null: false, default: false
      add :x, :integer, null: false
      add :y, :integer, null: false
      add :w, :integer, null: false
      add :h, :integer, null: false
      add :features, :binary, null: false
    end

    create unique_index(:glyphs, [:puzzle_id, :position])
    create index(:glyphs, [:symbol_id])
  end
end
