defmodule Subcipher.Repo.Migrations.CreateSteps do
  use Ecto.Migration

  # Additional decoding steps of a puzzle. Step 1 (symbols -> letters, from
  # the pictures) is implicit; each row here decodes the previous step's
  # output with a text cipher (`type`, see Subcipher.Steps) and its `params`.
  def change do
    create table(:steps) do
      add :puzzle_id, references(:puzzles, on_delete: :delete_all), null: false
      add :position, :integer, null: false
      add :type, :string, null: false
      add :params, :map, null: false, default: %{}

      timestamps(type: :utc_datetime)
    end

    create unique_index(:steps, [:puzzle_id, :position])
  end
end
