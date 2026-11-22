defmodule Subcipher.Repo.Migrations.CreateImages do
  use Ecto.Migration

  # A puzzle can now span several pictures. Each picture becomes an `images`
  # row and glyphs point at their picture; symbols stay per puzzle, so they
  # are shared by all of its pictures.
  def up do
    create table(:images) do
      add :puzzle_id, references(:puzzles, on_delete: :delete_all), null: false
      add :path, :string, null: false
      add :width, :integer, null: false
      add :height, :integer, null: false
      add :position, :integer, null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:images, [:puzzle_id, :position])

    alter table(:glyphs) do
      add :image_id, references(:images, on_delete: :delete_all)
    end

    # Existing puzzles: their single picture becomes their first image.
    execute """
    INSERT INTO images (puzzle_id, path, width, height, position, inserted_at, updated_at)
    SELECT id, image_path, image_width, image_height, 0, inserted_at, updated_at FROM puzzles
    """

    execute "UPDATE glyphs SET image_id = images.id FROM images WHERE images.puzzle_id = glyphs.puzzle_id"
    execute "ALTER TABLE glyphs ALTER COLUMN image_id SET NOT NULL"

    drop unique_index(:glyphs, [:puzzle_id, :position])
    create unique_index(:glyphs, [:image_id, :position])

    alter table(:puzzles) do
      remove :image_path
      remove :image_width
      remove :image_height
    end
  end

  # Keeps only the first picture of each puzzle.
  def down do
    alter table(:puzzles) do
      add :image_path, :string
      add :image_width, :integer
      add :image_height, :integer
    end

    execute """
    UPDATE puzzles SET image_path = i.path, image_width = i.width, image_height = i.height
    FROM (SELECT DISTINCT ON (puzzle_id) * FROM images ORDER BY puzzle_id, position) AS i
    WHERE i.puzzle_id = puzzles.id
    """

    execute """
    DELETE FROM glyphs WHERE image_id NOT IN
      (SELECT DISTINCT ON (puzzle_id) id FROM images ORDER BY puzzle_id, position)
    """

    execute "DELETE FROM symbols s WHERE NOT EXISTS (SELECT 1 FROM glyphs g WHERE g.symbol_id = s.id)"

    drop unique_index(:glyphs, [:image_id, :position])
    create unique_index(:glyphs, [:puzzle_id, :position])

    alter table(:glyphs) do
      remove :image_id
    end

    drop table(:images)
  end
end
