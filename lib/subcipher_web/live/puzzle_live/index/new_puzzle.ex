defmodule SubcipherWeb.PuzzleLive.Index.NewPuzzle do
  @moduledoc """
  A new puzzle, once its cipher is chosen: the cipher text (or pictures of
  its symbols) it decodes, and a title.
  """
  use SubcipherWeb, :html

  import SubcipherWeb.Components.OsrsUsage

  attr :cipher, :atom, required: true, doc: "the cipher of the first step"
  attr :input_kind, :string, required: true, doc: "\"text\" or \"pictures\""
  attr :input_kinds, :list, required: true, doc: "the input kinds of the cipher"
  attr :text_form, :any, required: true
  attr :current_scope, :any, required: true
  attr :guess_choice, :map, default: nil, doc: "the guess this puzzle starts from, if any"

  def new_puzzle(assigns) do
    ~H"""
    <div :if={@current_scope && @cipher} id="new-puzzle-input" class="space-y-4">
      <div class="flex items-start gap-3 rounded-xl border border-primary/40 bg-primary/5 p-4">
        <div class="flex-1 min-w-0 space-y-1">
          <p class="font-semibold">{@cipher.name()}</p>
          <p class="text-sm text-base-content/60">{@cipher.description()}</p>
          <.osrs_usage cipher={@cipher} />
        </div>
        <.link patch={~p"/"} id="change-cipher" class="btn btn-ghost shrink-0">
          <.icon name="hero-arrow-path-rounded-square" class="size-5" /> Change
        </.link>
      </div>

      <p
        :if={@guess_choice && @guess_choice.label}
        id="guess-choice"
        class="text-sm rounded-lg bg-secondary/10 px-3 py-2 flex items-center gap-2"
      >
        <.icon name="hero-sparkles" class="size-4 text-secondary shrink-0" />
        The guessed settings ({@guess_choice.label}) will be applied to the first step.
      </p>

      <%= if @input_kind == "pictures" do %>
        <.live_component
          module={SubcipherWeb.PictureUploadComponent}
          id="new-puzzle"
          scope={@current_scope}
        />
      <% else %>
        <.form
          for={@text_form}
          id="new-text-puzzle-form"
          phx-change="validate_text"
          phx-submit="create_text"
          class="space-y-1"
        >
          <.input
            field={@text_form[:input_text]}
            type="textarea"
            label="Cipher text"
            rows="7"
            placeholder={placeholder(@cipher)}
            class="w-full textarea font-mono text-lg leading-relaxed"
          />
          <div class="flex flex-col sm:flex-row gap-3 sm:items-end">
            <div class="flex-1">
              <.input field={@text_form[:title]} label="Title" placeholder="Zodiac 408" />
            </div>
            <.button
              variant="primary"
              class="btn btn-primary mb-2"
              phx-disable-with="Creating…"
            >
              Start decoding <.icon name="hero-arrow-right" class="size-4" />
            </.button>
          </div>
        </.form>
      <% end %>

      <p :if={length(@input_kinds) > 1} class="text-sm text-base-content/60">
        <%= for kind <- @input_kinds, kind != @input_kind do %>
          <.link
            patch={~p"/?cipher=#{@cipher.type()}&input=#{kind}"}
            id={"use-input-#{kind}"}
            class="link link-hover inline-flex items-center gap-1"
          >
            <.icon name={input_icon(kind)} class="size-4" /> {input_switch_label(kind)}
          </.link>
        <% end %>
      </p>
    </div>
    """
  end

  defp placeholder(cipher) do
    case cipher.type() do
      "morse" -> "-- --- .-. ... . / -.-. --- -.. ."
      "letter_numbers" -> "8 5 12 12 15 | 23 15 18 12 4"
      "ascii" -> "72 105 33"
      "unicode" -> "U+2600 U+0048 U+0069"
      "symbol_substitution" -> "☀♪Θ ♠Φ☎Θ"
      _ -> "Paste the cipher text here"
    end
  end

  defp input_icon("pictures"), do: "hero-photo"
  defp input_icon(_), do: "hero-document-text"

  defp input_switch_label("pictures"), do: "Upload pictures instead"
  defp input_switch_label(_), do: "Have it as text? Paste it instead"
end
