defmodule SubcipherWeb.PuzzleLive.SymbolStep.CipherText do
  @moduledoc """
  The cipher text of a pictures puzzle: its glyphs, picture by picture and
  line by line, each with the letter it stands for.
  """
  use SubcipherWeb, :html

  import SubcipherWeb.PuzzleLive.Pictures.Controls
  import SubcipherWeb.PuzzleLive.SymbolStep.GlyphCell

  attr :sections, :list, required: true, doc: "see SubcipherWeb.PuzzleLive.Sections"
  attr :symbols, :map, required: true, doc: "by id"
  attr :selected_symbol_id, :any, required: true
  attr :selected_glyph_id, :any, required: true
  attr :merging, :boolean, required: true
  attr :duplicates, :any, required: true, doc: "letters used by several symbols"

  def cipher_text(assigns) do
    ~H"""
    <section
      id="cipher-text"
      class="rounded-2xl border border-base-300 bg-base-100 p-4 sm:p-6 space-y-5 overflow-x-auto"
      phx-click="deselect"
    >
      <div
        :for={section <- @sections}
        id={"section-#{section.image.id}"}
        class="space-y-5 [&+&]:pt-6 [&+&]:border-t-2 [&+&]:border-base-300"
      >
        <div
          :if={length(@sections) > 1}
          class="flex items-center justify-between text-xs font-semibold uppercase tracking-wider text-base-content/50"
        >
          Picture {section.index}
          <.picture_controls section={section} count={length(@sections)} />
        </div>
        <div
          :for={line <- section.lines}
          id={"line-#{line.id}"}
          class="flex flex-wrap gap-x-5 gap-y-3 pb-5 border-b border-dashed border-base-300 last:border-0 last:pb-0"
        >
          <div :for={word <- line.words} class="flex items-start gap-1">
            <.glyph_cell
              :for={g <- word}
              glyph={g}
              line={line}
              symbol={@symbols[g.symbol_id]}
              image={section.image}
              scale={section.scale}
              selected={g.symbol_id == @selected_symbol_id}
              current={g.id == @selected_glyph_id}
              merging={@merging}
              duplicate={MapSet.member?(@duplicates, @symbols[g.symbol_id].letter)}
            />
          </div>
        </div>
      </div>
    </section>
    """
  end
end
