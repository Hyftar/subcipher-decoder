defmodule Subcipher.Repo.Migrations.AddGlyphSamplesAndTrims do
  use Ecto.Migration

  def change do
    alter table(:symbols) do
      # The occurrence shown for the symbol (and used by algorithms); nil =
      # the first one in reading order.
      add :sample_glyph_id, references(:glyphs, on_delete: :nilify_all)
    end

    alter table(:glyphs) do
      # The box found by detection, kept once the user trims the glyph (so
      # the crop can be reset); nil = never trimmed.
      add :detected_box, :map
    end
  end
end
