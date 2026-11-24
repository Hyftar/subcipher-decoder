defmodule SubcipherWeb.AlgorithmLive.Trace.ImageOptions do
  @moduledoc """
  The options of the symbol image: style, alignment, colours (detected or
  chosen) and transparency; and its PNG download (handled by the hook).
  """
  use SubcipherWeb, :html

  import SubcipherWeb.AlgorithmLive.Trace.ColourChoice

  attr :options, :map,
    required: true,
    doc: "style, align, background / ink (\"auto\" or #rrggbb), transparent"

  attr :detected, :map, required: true, doc: "the colours detected by the hook"

  def image_options(assigns) do
    ~H"""
    <div class="space-y-3">
      <div class="flex flex-wrap items-center gap-x-5 gap-y-2 text-sm">
        <div class="flex items-center gap-2">
          <span class="text-base-content/70">Style</span>
          <div id="image-style" class="join">
            <button
              :for={
                {style, label, title} <- [
                  {"original", "Original", "The glyphs as they are in the pictures"},
                  {"mask", "Two colours",
                   "The black and white pass of the pictures, as a font: glyphs in one colour on a plain background"}
                ]
              }
              type="button"
              id={"style-#{style}"}
              class={["btn btn-sm join-item", @options.style == style && "btn-primary"]}
              phx-click="image_style"
              phx-value-style={style}
              aria-pressed={to_string(@options.style == style)}
              title={title}
            >
              {label}
            </button>
          </div>
        </div>
        <div class="flex items-center gap-2">
          <span class="text-base-content/70">Align</span>
          <div id="image-align" class="join">
            <button
              :for={
                {align, icon} <- [
                  {"left", "hero-bars-3-bottom-left"},
                  {"center", "hero-bars-3"},
                  {"right", "hero-bars-3-bottom-right"}
                ]
              }
              type="button"
              id={"align-#{align}"}
              class={["btn btn-sm join-item", @options.align == align && "btn-primary"]}
              phx-click="image_align"
              phx-value-align={align}
              aria-pressed={to_string(@options.align == align)}
              aria-label={"Align #{align}"}
              title={"Align #{align}"}
            >
              <.icon name={icon} class="size-5" />
            </button>
          </div>
        </div>
        <button
          type="button"
          id="download-image"
          class="btn btn-sm btn-ghost ml-auto"
          data-download
        >
          <.icon name="hero-arrow-down-tray" class="size-5" /> Download PNG
        </button>
      </div>
      <form
        id="image-options"
        phx-change="image_options"
        class="flex flex-wrap items-center gap-x-5 gap-y-2 text-sm"
      >
        <.colour_choice
          :if={@options.style == "mask"}
          field="ink"
          label="Glyphs"
          value={@options.ink}
          detected={@detected.ink}
          title="The colour of the ink in the pictures"
        />
        <div class="flex items-center gap-2">
          <.colour_choice
            field="background"
            label="Background"
            value={@options.background}
            detected={@detected.background}
            disabled={@options.style == "mask" and @options.transparent}
            title="The colour around the glyphs in the pictures"
          />
          <button
            :if={@options.style == "mask"}
            type="button"
            id="background-transparent"
            phx-click="image_transparent"
            class={["btn btn-sm", @options.transparent && "btn-primary"]}
            aria-pressed={to_string(@options.transparent)}
            title="No background: a PNG to put on anything"
          >
            <span class="inline-block size-4 rounded-sm ring-1 ring-base-content/30 checkerboard"></span>
            Transparent
          </button>
        </div>
      </form>
    </div>
    """
  end
end
