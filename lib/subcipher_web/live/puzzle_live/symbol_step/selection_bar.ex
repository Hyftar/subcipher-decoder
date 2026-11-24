defmodule SubcipherWeb.PuzzleLive.SymbolStep.SelectionBar do
  @moduledoc """
  The selected symbol of a pictures puzzle and its actions (glyphs, merge,
  split, ignore); keyboard help when nothing is selected.
  """
  use SubcipherWeb, :html

  import SubcipherWeb.PuzzleLive.GlyphImage

  attr :symbol, :any, required: true
  attr :glyph_id, :any, required: true
  attr :merging, :boolean, required: true
  attr :show_glyphs, :boolean, default: false
  attr :key, :list, required: true
  attr :images, :map, required: true

  def selection_bar(%{symbol: nil} = assigns) do
    ~H"""
    <div class="rounded-xl bg-base-200/60 px-4 py-3 text-sm text-base-content/70 flex items-center gap-2">
      <.icon name="hero-cursor-arrow-rays" class="size-5 shrink-0" />
      <p id="keyboard-help">
        Click a symbol, then type the letter it stands for. Every identical symbol is replaced
        at once. <kbd class="kbd kbd-xs">←</kbd> <kbd class="kbd kbd-xs">→</kbd>
        previous / next character, <kbd class="kbd kbd-xs">↑</kbd> <kbd class="kbd kbd-xs">↓</kbd>
        previous / next symbol of the key, <kbd class="kbd kbd-xs">⌫</kbd>
        clears.
      </p>
    </div>
    """
  end

  def selection_bar(assigns) do
    assigns =
      assign(assigns, entry: Enum.find(assigns.key, &(&1.symbol.id == assigns.symbol.id)))

    ~H"""
    <div
      id="selection-bar"
      class={[
        "rounded-xl px-4 py-3 flex flex-wrap items-center gap-3 text-sm transition-colors",
        if(@merging, do: "bg-warning/15 ring-1 ring-warning", else: "bg-primary/10")
      ]}
    >
      <span class="grid place-items-center size-12 rounded-lg bg-base-100 shrink-0">
        <.glyph_image glyph={@entry.sample} image={@images[@entry.sample.image_id]} box={40} />
      </span>
      <div class="flex-1 min-w-40">
        <%= if @merging do %>
          <p class="font-medium">Click another symbol to merge it into this one.</p>
          <p class="text-base-content/70">Use this when the same symbol was detected twice.</p>
        <% else %>
          <p class="font-medium">
            {@entry.count} occurrence{if @entry.count > 1, do: "s"} ·
            <span :if={@symbol.letter}>
              stands for <span class="font-mono text-primary text-base">{@symbol.letter}</span>
            </span>
            <span :if={!@symbol.letter} class="text-base-content/70">type a letter…</span>
          </p>
        <% end %>
      </div>
      <div class="flex flex-wrap gap-2">
        <%= if @merging do %>
          <button type="button" class="btn" phx-click="cancel_merge">Cancel</button>
        <% else %>
          <button
            type="button"
            class={["btn", @show_glyphs && "btn-active"]}
            phx-click="toggle_glyphs"
            id="glyphs-button"
            aria-expanded={to_string(@show_glyphs)}
            title="Its occurrences: choose the one shown, trim a crop"
          >
            <.icon name="hero-squares-2x2" class="size-5" /> Glyphs
          </button>
          <button type="button" class="btn" phx-click="start_merge" id="merge-button">
            <.icon name="hero-arrows-pointing-in" class="size-5" /> Merge…
          </button>
          <button
            :if={@glyph_id && @entry.count > 1}
            type="button"
            class="btn"
            phx-click="detach"
            id="detach-button"
            title="This occurrence is actually a different symbol"
          >
            <.icon name="hero-scissors" class="size-5" /> Split this one off
          </button>
          <button
            type="button"
            class="btn"
            phx-click="toggle_ignore"
            phx-value-id={@symbol.id}
            title="Hide noise or decorations from the text"
          >
            <.icon name={if @symbol.ignored, do: "hero-eye", else: "hero-eye-slash"} class="size-5" />
            {if @symbol.ignored, do: "Restore", else: "Ignore"}
          </button>
        <% end %>
      </div>
    </div>
    """
  end
end
