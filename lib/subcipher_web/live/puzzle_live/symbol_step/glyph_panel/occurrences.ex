defmodule SubcipherWeb.PuzzleLive.SymbolStep.GlyphPanel.Occurrences do
  @moduledoc """
  The occurrences of the selected symbol: pick one to trim it; its sample
  (the one shown in the symbol key and drawn by algorithms) is starred.
  """
  use SubcipherWeb, :html

  import SubcipherWeb.PuzzleLive.GlyphImage

  attr :entry, :any, required: true, doc: "the selected symbol's key entry"
  attr :glyph, :any, required: true, doc: "the occurrence edited"
  attr :images, :map, required: true

  def occurrences(assigns) do
    ~H"""
    <div class="space-y-2 min-w-0">
      <h3 class="text-sm font-semibold">
        Occurrences <span class="text-base-content/50 font-normal">· {@entry.count}</span>
      </h3>
      <p class="text-xs text-base-content/60">
        Pick one to trim it. The <.icon name="hero-star-solid" class="size-3 text-warning" />
        sample is the one shown in the symbol key and drawn by algorithms.
      </p>
      <div id="occurrences" class="flex flex-wrap gap-1.5 max-h-56 overflow-y-auto p-0.5">
        <button
          :for={g <- @entry.glyphs}
          type="button"
          id={"occurrence-#{g.id}"}
          phx-click="edit_glyph"
          phx-value-id={g.id}
          aria-pressed={to_string(g.id == @glyph.id)}
          title={if g.detected_box, do: "Trimmed", else: nil}
          class={[
            "relative grid place-items-center size-12 rounded-lg bg-base-200/60 transition",
            "hover:bg-base-200 hover:-translate-y-0.5 focus:outline-none focus-visible:ring-2 focus-visible:ring-primary",
            g.id == @glyph.id && "ring-2 ring-primary bg-primary/10"
          ]}
        >
          <.glyph_image glyph={g} image={@images[g.image_id]} box={40} />
          <.icon
            :if={g.id == @entry.sample.id}
            name="hero-star-solid"
            class="absolute -top-1 -right-1 size-4 text-warning drop-shadow"
          />
          <.icon
            :if={g.detected_box}
            name="hero-scissors"
            class="absolute -bottom-1 -right-1 size-3.5 text-base-content/60"
          />
        </button>
      </div>
    </div>
    """
  end
end
