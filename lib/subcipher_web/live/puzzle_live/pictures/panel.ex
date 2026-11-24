defmodule SubcipherWeb.PuzzleLive.Pictures.Panel do
  @moduledoc """
  The original pictures of a puzzle with the symbols detected in them
  (collapsible), and the regrouping of symbols by tolerance.
  """
  use SubcipherWeb, :html

  import SubcipherWeb.PuzzleLive.Pictures.Controls

  attr :puzzle, :any, required: true
  attr :sections, :list, required: true, doc: "see SubcipherWeb.PuzzleLive.Sections"
  attr :symbols, :map, required: true, doc: "by id"
  attr :selected_symbol_id, :any, required: true
  attr :show, :boolean, required: true, doc: "expanded"
  attr :tolerance, :integer, required: true, doc: "of the grouping, in thousandths"

  def pictures_panel(assigns) do
    ~H"""
    <section class="rounded-2xl border border-base-300 bg-base-100">
      <button
        type="button"
        phx-click="toggle_image"
        class="w-full flex items-center justify-between px-4 py-2 text-sm font-semibold"
      >
        {if length(@puzzle.images) > 1,
          do: "Original pictures & detected symbols",
          else: "Original picture & detected symbols"}
        <.icon
          name={if @show, do: "hero-chevron-up", else: "hero-chevron-down"}
          class="size-4"
        />
      </button>
      <div :if={@show} class="p-4 pt-0 space-y-4">
        <figure
          :for={section <- @sections}
          id={"picture-#{section.image.id}"}
          class="space-y-2"
        >
          <figcaption
            :if={length(@sections) > 1}
            class="flex items-center justify-between text-xs font-semibold uppercase tracking-wider text-base-content/50"
          >
            Picture {section.index}
            <span class="flex items-center gap-1">
              <.picture_controls
                section={section}
                count={length(@sections)}
                id_prefix="panel-"
              />
              <button
                type="button"
                class="btn btn-ghost btn-sm normal-case tracking-normal font-normal"
                phx-click="delete_image"
                phx-value-id={section.image.id}
                data-confirm="Remove this picture? Symbols that only appear in it are removed too."
              >
                <.icon name="hero-trash" class="size-5" /> Remove
              </button>
            </span>
          </figcaption>
          <div class="relative">
            <img
              src={section.image.path}
              alt={"Cipher picture #{section.index}"}
              class="block w-full h-auto rounded-lg"
            />
            <button
              :for={g <- section.glyphs}
              type="button"
              phx-click="select_glyph"
              phx-value-id={g.id}
              aria-label="Select symbol"
              class={[
                "absolute rounded-[2px] ring-1 transition",
                cond do
                  g.symbol_id == @selected_symbol_id -> "ring-2 ring-primary bg-primary/25"
                  @symbols[g.symbol_id].ignored -> "ring-base-content/20"
                  @symbols[g.symbol_id].letter -> "ring-success/70 bg-success/10"
                  true -> "ring-warning/70 hover:bg-warning/20"
                end
              ]}
              style={box_style(g, section.image)}
            />
          </div>
        </figure>
        <.form
          for={%{}}
          id="regroup-form"
          phx-submit="regroup"
          class="mt-4 flex flex-wrap items-end gap-3 text-sm"
        >
          <label class="flex-1 min-w-56">
            <span class="block font-medium mb-1">
              Grouping tolerance
              <span class="text-base-content/60 font-normal">
                (higher = more glyphs considered identical)
              </span>
            </span>
            <input
              type="range"
              name="tolerance"
              min="5"
              max="150"
              value={@tolerance}
              class="range range-primary range-sm"
            />
          </label>
          <button
            type="submit"
            class="btn"
            data-confirm="Regroup all symbols? Letters are kept when all glyphs of a new group agree."
          >
            Regroup symbols
          </button>
        </.form>
      </div>
    </section>
    """
  end

  defp box_style(g, image) do
    "left: #{g.x / image.width * 100}%; top: #{g.y / image.height * 100}%; " <>
      "width: #{g.w / image.width * 100}%; height: #{g.h / image.height * 100}%"
  end
end
