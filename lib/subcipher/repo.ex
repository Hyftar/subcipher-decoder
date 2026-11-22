defmodule Subcipher.Repo do
  use Ecto.Repo,
    otp_app: :subcipher,
    adapter: Ecto.Adapters.Postgres
end
