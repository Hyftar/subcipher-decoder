# Seeds the database:
#
#     mix run priv/repo/seeds.exs
#
# Creates the admin user (ADMIN_EMAIL, default admin@subcipher.local), already
# confirmed: log in with a link sent to that address (in development, read
# it in MailDev, http://localhost:1080). Puzzles and algorithms without an
# owner are given to it. Safe to run several times.

import Ecto.Query

alias Subcipher.{Accounts, Repo}
alias Subcipher.Accounts.User
alias Subcipher.Algorithms.Algorithm
alias Subcipher.Ciphers.Puzzle

email = System.get_env("ADMIN_EMAIL", "admin@subcipher.local")

admin =
  Accounts.get_user_by_email(email) ||
    Repo.insert!(%User{email: email, confirmed_at: DateTime.utc_now(:second)})

for schema <- [Puzzle, Algorithm] do
  Repo.update_all(from(r in schema, where: is_nil(r.user_id)), set: [user_id: admin.id])
end

IO.puts("Admin user: #{admin.email}")
