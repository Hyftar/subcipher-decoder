defmodule SubcipherWeb.PuzzleLive.SymbolStep.SymbolKey do
  @moduledoc """
  The symbols of a pictures puzzle, most frequent first, each with its
  frequency and the letter it stands for (editable by the owner only).
  """
  use SubcipherWeb, :html

  import SubcipherWeb.PuzzleLive.GlyphImage

  attr :key, :list, required: true
  attr :images, :map, required: true
  attr :selected_symbol_id, :any, required: true
  attr :duplicates, :any, required: true
  attr :english_frequency, :string, required: true
  attr :owner, :boolean, default: true, doc: "false: letters are shown, not editable"

  def symbol_key(assigns) do
    ~H"""
    <aside class="space-y-3 lg:sticky lg:top-20 lg:self-start">
      <div class="flex items-center justify-between">
        <h2 class="font-semibold">Symbol key</h2>
        <button
          :if={@owner}
          type="button"
          id="reset-letters"
          class="btn btn-ghost btn-sm"
          phx-click="reset_letters"
          data-confirm="Clear every letter?"
        >
          <.icon name="hero-arrow-path" class="size-5" /> Reset
        </button>
      </div>
      <p class="text-xs text-base-content/60">
        Most frequent first. English letters by frequency:
        <span class="font-mono tracking-wider">{@english_frequency}</span>
      </p>
      <ul
        id="symbol-key"
        class="rounded-2xl border border-base-300 bg-base-100 divide-y divide-base-300 lg:max-h-[calc(100vh-12rem)] overflow-y-auto"
      >
        <li
          :for={entry <- @key}
          id={"symbol-#{entry.symbol.id}"}
          class={[
            "flex items-center gap-3 px-3 py-2 transition-colors",
            entry.symbol.id == @selected_symbol_id && "bg-primary/10",
            entry.symbol.ignored && "opacity-40"
          ]}
        >
          <button
            type="button"
            phx-click="select_symbol"
            phx-value-id={entry.symbol.id}
            class="flex flex-1 items-center gap-3 min-w-0 text-left"
          >
            <span class="grid place-items-center size-10 rounded-md bg-base-200/60 shrink-0">
              <.glyph_image glyph={entry.sample} image={@images[entry.sample.image_id]} box={32} />
            </span>
            <span class="text-xs text-base-content/70 leading-tight">
              <span class="block font-medium text-base-content">×{entry.count}</span>
              {if entry.symbol.ignored, do: "ignored", else: "#{Float.round(entry.frequency, 1)}%"}
            </span>
          </button>
          <span
            :if={!@owner and !entry.symbol.ignored}
            id={"letter-#{entry.symbol.id}"}
            class={[
              "grid place-items-center min-w-14 h-8 px-2 rounded-md font-mono uppercase text-base",
              entry.symbol.letter && !MapSet.member?(@duplicates, entry.symbol.letter) &&
                "text-primary font-semibold",
              entry.symbol.letter && MapSet.member?(@duplicates, entry.symbol.letter) &&
                "text-warning font-semibold",
              !entry.symbol.letter && "text-base-content/30"
            ]}
          >
            {entry.symbol.letter || "_"}
          </span>
          <form
            :if={@owner and !entry.symbol.ignored}
            phx-change="assign"
            phx-submit="assign"
            id={"assign-#{entry.symbol.id}"}
          >
            <input type="hidden" name="symbol_id" value={entry.symbol.id} />
            <input
              type="text"
              name="letter"
              value={entry.symbol.letter}
              maxlength="3"
              autocomplete="off"
              spellcheck="false"
              aria-label="Letter"
              phx-debounce="150"
              class={[
                "input input-sm w-14 text-center font-mono uppercase text-base",
                MapSet.member?(@duplicates, entry.symbol.letter) && "input-warning"
              ]}
            />
          </form>
        </li>
      </ul>
      <p :if={MapSet.size(@duplicates) > 0} class="text-xs text-warning">
        <.icon name="hero-exclamation-triangle" class="size-4 align-text-bottom" />
        Used by several symbols: {Enum.join(@duplicates, ", ")}
      </p>
    </aside>
    """
  end
end
