defmodule Subcipher.Repo.Migrations.MergeCharacterCodeCiphers do
  use Ecto.Migration

  # The binary/hexadecimal ASCII and Unicode ciphers became two ciphers,
  # "ascii" and "unicode", with a `base` setting. Steps of puzzles and of
  # algorithms are renamed, their base set; their other settings (width,
  # encoding) are kept.
  @renames [
    {"binary_ascii", "ascii", "2"},
    {"hex_ascii", "ascii", "16"},
    {"binary_unicode", "unicode", "2"},
    {"hex_unicode", "unicode", "16"}
  ]

  def up do
    for {old, new, base} <- @renames do
      execute """
      UPDATE steps
      SET type = '#{new}', params = params || '{"base": "#{base}"}'::jsonb
      WHERE type = '#{old}'
      """

      execute """
      UPDATE algorithms
      SET steps = ARRAY(
        SELECT CASE WHEN s->>'type' = '#{old}'
          THEN s || jsonb_build_object(
            'type', '#{new}',
            'params', COALESCE(s->'params', '{}'::jsonb) || '{"base": "#{base}"}'::jsonb
          )
          ELSE s END
        FROM unnest(steps) WITH ORDINALITY AS t(s, i)
        ORDER BY i
      )
      WHERE EXISTS (SELECT 1 FROM unnest(steps) AS s WHERE s->>'type' = '#{old}')
      """
    end
  end

  # Decimal steps had no cipher before: they are left as they are.
  def down do
    for {old, new, base} <- @renames do
      execute """
      UPDATE steps
      SET type = '#{old}', params = params - 'base'
      WHERE type = '#{new}' AND params->>'base' = '#{base}'
      """

      execute """
      UPDATE algorithms
      SET steps = ARRAY(
        SELECT CASE WHEN s->>'type' = '#{new}' AND s->'params'->>'base' = '#{base}'
          THEN s || jsonb_build_object('type', '#{old}', 'params', (s->'params') - 'base')
          ELSE s END
        FROM unnest(steps) WITH ORDINALITY AS t(s, i)
        ORDER BY i
      )
      WHERE EXISTS (
        SELECT 1 FROM unnest(steps) AS s
        WHERE s->>'type' = '#{new}' AND s->'params'->>'base' = '#{base}'
      )
      """
    end
  end
end
