defmodule SubcipherWeb.PuzzleLive.SymbolStep.GlyphPanel do
  @moduledoc """
  The occurrences of the selected symbol: choose the one shown for it (and
  used by algorithms), and trim the crop of any of them.
  """
  use SubcipherWeb, :html

  import SubcipherWeb.PuzzleLive.SymbolStep.GlyphPanel.{CropEditor, Occurrences}

  attr :entry, :any, required: true, doc: "the selected symbol's key entry"
  attr :glyph_id, :any, required: true, doc: "the occurrence to edit (else the sample)"
  attr :images, :map, required: true
  attr :view, :string, required: true, doc: "\"original\" or \"mask\""

  def glyph_panel(%{entry: nil} = assigns), do: ~H""

  def glyph_panel(assigns) do
    glyph =
      Enum.find(assigns.entry.glyphs, &(&1.id == assigns.glyph_id)) || assigns.entry.sample

    assigns = assign(assigns, glyph: glyph, image: assigns.images[glyph.image_id])

    ~H"""
    <section
      id="glyph-panel"
      class="rounded-2xl border border-base-300 bg-base-100 p-4 grid gap-5 md:grid-cols-[minmax(0,1fr)_18rem]"
    >
      <.occurrences entry={@entry} glyph={@glyph} images={@images} />
      <.crop_editor entry={@entry} glyph={@glyph} image={@image} view={@view} />
    </section>
    """
  end
end
