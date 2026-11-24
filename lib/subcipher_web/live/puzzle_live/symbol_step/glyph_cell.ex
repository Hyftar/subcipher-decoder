defmodule SubcipherWeb.PuzzleLive.SymbolStep.GlyphCell do
  @moduledoc "A glyph of the cipher text, with the letter its symbol stands for."
  use SubcipherWeb, :html

  import SubcipherWeb.PuzzleLive.GlyphImage

  attr :glyph, :any, required: true
  attr :line, :map, required: true
  attr :symbol, :any, required: true
  attr :image, :any, required: true
  attr :scale, :float, required: true
  attr :selected, :boolean, required: true
  attr :current, :boolean, required: true
  attr :merging, :boolean, required: true
  attr :duplicate, :boolean, required: true

  def glyph_cell(assigns) do
    ~H"""
    <button
      type="button"
      id={"glyph-#{@glyph.id}"}
      phx-click="select_glyph"
      phx-value-id={@glyph.id}
      class={[
        "group flex flex-col items-center rounded-md px-0.5 pt-1 transition",
        "focus:outline-none focus-visible:ring-2 focus-visible:ring-primary",
        @symbol.ignored && "opacity-25",
        @selected && !@merging && "bg-primary/15",
        @selected && @merging && "bg-warning/25",
        !@selected && @merging && "hover:bg-warning/15 cursor-copy",
        !@selected && !@merging && "hover:bg-base-200",
        @current && "ring-2 ring-primary"
      ]}
    >
      <span class="relative block" style={"height: #{px(@line.height * @scale)}"}>
        <span
          class="block"
          style={"margin-top: #{px((@glyph.y - @line.top) * @scale)}"}
        >
          <.glyph_image glyph={@glyph} image={@image} scale={@scale} />
        </span>
      </span>
      <span
        :if={!@symbol.ignored}
        class={[
          "mt-1 min-w-6 h-7 border-b-2 text-center font-mono text-lg leading-7 uppercase",
          @symbol.letter && !@duplicate && "border-transparent text-primary font-semibold",
          @symbol.letter && @duplicate && "border-transparent text-warning font-semibold",
          !@symbol.letter && "border-base-content/30 text-transparent",
          @selected && "border-primary!"
        ]}
      >
        {@symbol.letter || "_"}
      </span>
    </button>
    """
  end

  defp px(v), do: "#{Float.round(v * 1.0, 2)}px"
end
