defmodule SubcipherWeb.AlgorithmLive.SavePanel do
  @moduledoc """
  Saving an opened cipher (a draft) as a puzzle: its title, for a logged-in
  user; an invitation to sign up or log in otherwise.
  """
  use SubcipherWeb, :html

  import SubcipherWeb.Components.FieldErrors

  attr :current_scope, :any, required: true
  attr :form, :any, required: true, doc: "the puzzle's title (and errors)"
  attr :mode, :string, required: true, doc: "\"encode\" or \"decode\""
  attr :cipher_text, :string, required: true, doc: "what the puzzle would decode"

  def save_panel(assigns) do
    assigns = assign(assigns, empty?: String.trim(assigns.cipher_text) == "")

    ~H"""
    <section
      id="save-draft"
      class="scroll-mt-24 rounded-2xl border border-primary/30 bg-gradient-to-br from-primary/10 via-base-100 to-base-100 p-5 sm:p-6 space-y-4"
    >
      <div class="flex items-start gap-3">
        <div class="grid place-items-center size-10 shrink-0 rounded-xl bg-primary text-primary-content shadow-sm">
          <.icon
            name={if @current_scope, do: "hero-bookmark", else: "hero-lock-closed"}
            class="size-5"
          />
        </div>
        <div class="space-y-0.5">
          <h2 class="font-semibold">Save as a puzzle</h2>
          <p :if={@current_scope} class="text-sm text-base-content/70">
            Keeps these steps and {source(@mode)} in your puzzles: come back to it, share
            it, or make an algorithm of it.
          </p>
          <p :if={!@current_scope} class="text-sm text-base-content/70">
            Create an account to keep these steps and {source(@mode)} as a puzzle, share
            it, and make an algorithm of it. We email you a link, no password needed.
          </p>
        </div>
      </div>

      <%= if @current_scope do %>
        <.form
          for={@form}
          id="save-puzzle-form"
          phx-change="validate_save"
          phx-submit="save_puzzle"
          class="space-y-1"
        >
          <div class="flex flex-row items-center gap-3">
            <div class="flex-1">
              <.input field={@form[:title]} label="Title" maxlength="120" />
            </div>
            <.button
              id="save-puzzle"
              variant="primary"
              class="btn btn-primary mb-2 mt-6"
              disabled={@empty?}
              phx-disable-with="Saving..."
            >
              <.icon name="hero-bookmark" class="size-4" /> Save puzzle
            </.button>
          </div>
          <p
            :if={@empty?}
            id="save-needs-text"
            class="flex items-center gap-1.5 text-sm text-base-content/60"
          >
            <.icon name="hero-information-circle" class="size-6 shrink-0" />
            {if @mode == "decode",
              do: "Type the cipher text to decode first.",
              else: "Type a message to encode first."}
          </p>
          <.field_errors form_field={@form[:input_text]} />
        </.form>
      <% else %>
        <div id="save-draft-login" class="flex flex-wrap gap-2">
          <.link navigate={~p"/users/register"} class="btn btn-primary">
            Sign up <.icon name="hero-arrow-right" class="size-5" />
          </.link>
          <.link navigate={~p"/users/log-in"} class="btn btn-ghost">Log in</.link>
        </div>
      <% end %>
    </section>
    """
  end

  defp source("decode"), do: "the cipher text you are decoding"
  defp source(_), do: "the encoded message"
end
