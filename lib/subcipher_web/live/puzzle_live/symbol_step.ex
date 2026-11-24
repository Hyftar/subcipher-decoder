defmodule SubcipherWeb.PuzzleLive.SymbolStep do
  @moduledoc """
  Step 1 of a pictures puzzle: the symbols of the pictures, substituted by
  hand, with the symbol key. Keyboard shortcuts come from the `.CipherKeys`
  hook.
  """
  use SubcipherWeb, :html

  import SubcipherWeb.Components.{Output, SuggestionsPanel}

  import SubcipherWeb.PuzzleLive.Pictures.{AddPanel, Panel}
  import SubcipherWeb.PuzzleLive.SymbolStep.{CipherText, GlyphPanel, SelectionBar, SymbolKey}

  attr :puzzle, :any, required: true
  attr :selected_symbol_id, :any, required: true
  attr :selected_glyph_id, :any, required: true
  attr :merging, :boolean, required: true
  attr :key, :list, required: true
  attr :images, :map, required: true
  attr :symbols, :map, required: true
  attr :sections, :list, required: true
  attr :duplicates, :any, required: true
  attr :plaintext, :string, required: true
  attr :show_image, :boolean, required: true
  attr :show_add, :boolean, required: true
  attr :show_glyphs, :boolean, required: true
  attr :edited_glyph_id, :any, required: true
  attr :current_scope, :any, required: true
  attr :glyph_view, :string, required: true
  attr :tolerance, :integer, required: true
  attr :english_frequency, :string, required: true
  attr :symbol_suggestions, :list, required: true
  attr :symbol_solver, :map, required: true
  attr :suggestions_shown, :boolean, required: true

  def symbol_step(assigns) do
    ~H"""
    <div
      id="puzzle"
      phx-hook=".CipherKeys"
      data-selected={to_string(@selected_symbol_id != nil)}
      data-scroll-to={
        cond do
          @selected_glyph_id -> "glyph-#{@selected_glyph_id}"
          @selected_symbol_id -> "symbol-#{@selected_symbol_id}"
          true -> nil
        end
      }
    >
      <div class="grid gap-6 lg:grid-cols-[minmax(0,1fr)_20rem]">
        <div class="space-y-6 min-w-0">
          <.selection_bar
            symbol={@symbols[@selected_symbol_id]}
            glyph_id={@selected_glyph_id}
            merging={@merging}
            key={@key}
            images={@images}
            show_glyphs={@show_glyphs}
          />

          <.glyph_panel
            :if={@show_glyphs and @selected_symbol_id != nil and !@merging}
            entry={Enum.find(@key, &(&1.symbol.id == @selected_symbol_id))}
            glyph_id={@edited_glyph_id || @selected_glyph_id}
            images={@images}
            view={@glyph_view}
          />

          <.cipher_text
            sections={@sections}
            symbols={@symbols}
            selected_symbol_id={@selected_symbol_id}
            selected_glyph_id={@selected_glyph_id}
            merging={@merging}
            duplicates={@duplicates}
          />

          <section
            id="step-1-output"
            class="rounded-2xl border border-base-300 bg-base-100 p-4 sm:p-6 space-y-2"
          >
            <h2 class="text-xs font-semibold uppercase tracking-wider text-base-content/50">
              Output
            </h2>
            <.output id="plaintext" text={@plaintext} />
          </section>

          <section class="rounded-2xl border border-base-300 bg-base-100 p-4 sm:p-6">
            <.suggestions_panel
              id="symbols"
              suggestions={@symbol_suggestions}
              solver={@symbol_solver}
              shown={@suggestions_shown}
            />
          </section>

          <.pictures_panel
            puzzle={@puzzle}
            sections={@sections}
            symbols={@symbols}
            selected_symbol_id={@selected_symbol_id}
            show={@show_image}
            tolerance={@tolerance}
          />

          <.add_picture_panel puzzle={@puzzle} current_scope={@current_scope} show={@show_add} />
        </div>

        <.symbol_key
          key={@key}
          images={@images}
          selected_symbol_id={@selected_symbol_id}
          duplicates={@duplicates}
          english_frequency={@english_frequency}
        />
      </div>
      <script :type={Phoenix.LiveView.ColocatedHook} name=".CipherKeys">
        // Keyboard shortcuts on the puzzle page (handled by the LiveView):
        //   letter / digit      substitute the selected symbol
        //   Backspace / Delete  clear it
        //   ← / →               previous / next character of the text
        //   ↑ / ↓, Tab          previous / next symbol of the symbol key
        //   Escape              deselect
        // Ignored while typing in a form field, or inside [data-own-keys] (widgets
        // with their own keys, like the crop editor).
        //
        // The element's `data-scroll-to` names the selected glyph (or key row); it is
        // scrolled into view when the selection changes, so keyboard navigation
        // never leaves the selection off-screen.
        const NAV_KEYS = new Set(["ArrowRight", "ArrowLeft", "ArrowDown", "ArrowUp", "Tab", "Escape", "Backspace", "Delete"])

        export default {
          mounted() {
            this.scrolledTo = this.el.dataset.scrollTo
            this.onKeydown = (e) => {
              if (e.ctrlKey || e.metaKey || e.altKey) return
              const t = e.target
              if (t.closest?.("input, textarea, select, [contenteditable], [data-own-keys]")) return

              const isChar = e.key.length === 1 && e.key !== " "
              if (!isChar && !NAV_KEYS.has(e.key)) return
              if (e.key === "Tab" && this.el.dataset.selected !== "true") return

              e.preventDefault()
              this.pushEvent("key", { key: e.key, shift: e.shiftKey })
            }
            window.addEventListener("keydown", this.onKeydown)
          },

          updated() {
            const target = this.el.dataset.scrollTo
            if (!target || target === this.scrolledTo) {
              this.scrolledTo = target
              return
            }
            this.scrolledTo = target
            document.getElementById(target)?.scrollIntoView({ block: "nearest", inline: "nearest", behavior: "smooth" })
          },

          destroyed() {
            window.removeEventListener("keydown", this.onKeydown)
          },
        }
      </script>
    </div>
    """
  end
end
