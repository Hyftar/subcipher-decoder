defmodule Subcipher.Repo.Migrations.AddOwnersAndVisibility do
  use Ecto.Migration

  # Puzzles and algorithms belong to a user, and are private unless made
  # public. The ones made before accounts existed go to the admin user
  # (ADMIN_EMAIL, created here if needed; also seeded by priv/repo/seeds.exs),
  # so every row has an owner.
  def up do
    for table <- [:puzzles, :algorithms] do
      alter table(table) do
        add :user_id, references(:users, on_delete: :delete_all)
        add :public, :boolean, null: false, default: false
      end
    end

    flush()

    email = System.get_env("ADMIN_EMAIL", "admin@subcipher.local")

    execute("""
    INSERT INTO users (email, confirmed_at, inserted_at, updated_at)
    SELECT '#{String.replace(email, "'", "''")}', now(), now(), now()
    WHERE EXISTS (SELECT 1 FROM puzzles) OR EXISTS (SELECT 1 FROM algorithms)
    ON CONFLICT (email) DO NOTHING
    """)

    for table <- [:puzzles, :algorithms] do
      execute("""
      UPDATE #{table} SET user_id = (SELECT id FROM users WHERE email = '#{String.replace(email, "'", "''")}')
      WHERE user_id IS NULL
      """)

      execute("ALTER TABLE #{table} ALTER COLUMN user_id SET NOT NULL")
      create index(table, [:user_id])
      create index(table, [:public])
    end
  end

  def down do
    for table <- [:puzzles, :algorithms] do
      alter table(table) do
        remove :user_id
        remove :public
      end
    end
  end
end
