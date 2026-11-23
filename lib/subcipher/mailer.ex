defmodule Subcipher.Mailer do
  @moduledoc """
  Sends emails (sign-in links). Configured from environment variables in
  `config/runtime.exs` (SMTP; MailDev in development).
  """
  use Swoosh.Mailer, otp_app: :subcipher
end
