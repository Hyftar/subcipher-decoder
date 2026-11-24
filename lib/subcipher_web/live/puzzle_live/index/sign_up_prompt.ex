defmodule SubcipherWeb.PuzzleLive.Index.SignUpPrompt do
  @moduledoc "Invites visitors to create an account to start decoding."
  use SubcipherWeb, :html

  def sign_up_prompt(assigns) do
    ~H"""
    <div
      id="sign-up-prompt"
      class="rounded-2xl border border-primary/30 bg-gradient-to-br from-primary/10 to-base-100 p-6 sm:p-8 space-y-4"
    >
      <div class="grid place-items-center size-12 rounded-xl bg-primary text-primary-content">
        <.icon name="hero-key" class="size-6" />
      </div>
      <div class="space-y-1">
        <h2 class="text-lg font-semibold">Create an account to start decoding</h2>
        <p class="text-sm text-base-content/70">
          Your puzzles and algorithms are private unless you share them. Sign up with
          your email: we send you a link, no password needed.
        </p>
      </div>
      <div class="flex flex-wrap gap-2">
        <.link navigate={~p"/users/register"} class="btn btn-primary">
          Sign up <.icon name="hero-arrow-right" class="size-5" />
        </.link>
        <.link navigate={~p"/users/log-in"} class="btn btn-ghost">Log in</.link>
      </div>
    </div>
    """
  end
end
