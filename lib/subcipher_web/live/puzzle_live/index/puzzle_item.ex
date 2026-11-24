defmodule SubcipherWeb.PuzzleLive.Index.PuzzleItem do
  @moduledoc "A puzzle in a list: its picture or cipher, title and progress."
  use SubcipherWeb, :html

  alias Subcipher.Ciphers.Puzzle

  attr :row, :map, required: true, doc: "an entry of Ciphers.list_puzzles/1"
  attr :owned, :boolean, default: false, doc: "the user's own: deletable, shows visibility"

  def puzzle_item(assigns) do
    assigns = assign(assigns, p: assigns.row.puzzle)

    ~H"""
    <li
      id={if @owned, do: "puzzle-#{@p.id}", else: "public-puzzle-#{@p.id}"}
      class="group flex items-center gap-3 rounded-xl border border-base-300 bg-base-100 p-2 pr-3 transition hover:border-primary/50 hover:shadow-sm"
    >
      <.link navigate={~p"/puzzles/#{@p}"} class="flex flex-1 items-center gap-3 min-w-0">
        <span class="relative shrink-0">
          <span
            :if={!Puzzle.pictures?(@p)}
            class="grid place-items-center size-14 rounded-lg bg-base-200 font-mono text-xs text-base-content/60 overflow-hidden p-1 leading-tight break-all"
          >
            {String.slice(@p.input_text, 0, 24)}
          </span>
          <img
            :if={cover = Puzzle.pictures?(@p) && List.first(@p.images)}
            src={cover.path}
            alt=""
            class="size-14 rounded-lg object-cover bg-base-200"
          />
          <span
            :if={length(@p.images) > 1}
            class="absolute -bottom-1 -right-1 badge badge-xs badge-neutral"
            title={"#{length(@p.images)} pictures"}
          >
            ×{length(@p.images)}
          </span>
        </span>
        <div class="min-w-0 flex-1">
          <p class="flex items-center gap-1.5 font-medium">
            <span class="truncate">{@p.title}</span>
            <.icon
              :if={@owned and @p.public}
              name="hero-globe-alt"
              class="size-4 shrink-0 text-primary"
            />
          </p>
          <p class="text-xs text-base-content/60">
            <%= if Puzzle.pictures?(@p) do %>
              {pictures(length(@p.images))} · {@row.glyph_count} glyphs · {@row.symbol_count} symbols
            <% else %>
              Text · {String.length(@p.input_text)} characters
            <% end %>
          </p>
          <div
            :if={Puzzle.pictures?(@p)}
            class="mt-1 h-1.5 rounded-full bg-base-200 overflow-hidden"
          >
            <div
              class="h-full bg-primary transition-all"
              style={"width: #{percent(@row.solved_count, @row.symbol_count)}%"}
            />
          </div>
        </div>
      </.link>
      <button
        :if={@owned}
        type="button"
        phx-click="delete"
        phx-value-id={@p.id}
        data-confirm={"Delete “#{@p.title}”?"}
        class="btn btn-ghost btn-square opacity-0 group-hover:opacity-100 focus:opacity-100"
        aria-label={"Delete #{@p.title}"}
      >
        <.icon name="hero-trash" class="size-5" />
      </button>
    </li>
    """
  end

  defp pictures(1), do: "1 picture"
  defp pictures(n), do: "#{n} pictures"

  defp percent(_, 0), do: 0
  defp percent(n, total), do: round(n / total * 100)
end
