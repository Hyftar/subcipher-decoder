defmodule Subcipher.Repo.Migrations.AddInputToPuzzles do
  use Ecto.Migration

  # A puzzle's input is either pictures (step 1 is then the picture symbol
  # substitution, as before) or text, decoded by its stored steps only.
  def change do
    alter table(:puzzles) do
      add :input_kind, :string, null: false, default: "pictures"
      add :input_text, :text, null: false, default: ""
    end
  end
end
