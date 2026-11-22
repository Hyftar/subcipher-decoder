defmodule SubcipherWeb.PuzzleLive.Index do
  use SubcipherWeb, :live_view

  alias Subcipher.Ciphers

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Puzzles")
     |> assign(:puzzles, Ciphers.list_puzzles())}
  end

  @impl true
  def handle_event("delete", %{"id" => id}, socket) do
    puzzle = Ciphers.get_puzzle!(id)
    {:ok, _} = Ciphers.delete_puzzle(puzzle)

    {:noreply,
     socket
     |> put_flash(:info, "Puzzle deleted.")
     |> assign(:puzzles, Ciphers.list_puzzles())}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <section class="grid gap-8 lg:grid-cols-[minmax(0,3fr)_minmax(0,2fr)]">
        <div class="space-y-4">
          <div>
            <h1 class="text-2xl font-bold tracking-tight">Crack a substitution cipher</h1>
            <p class="text-base-content/70 mt-1">
              Upload a picture of the cipher text. Every symbol is detected and identical
              symbols are grouped, so you can substitute them with letters until the message
              appears. More pictures of the same cipher can be added afterwards.
            </p>
          </div>

          <.live_component module={SubcipherWeb.PictureUploadComponent} id="new-puzzle" />
        </div>

        <aside class="space-y-3">
          <h2 class="font-semibold text-base-content/80">Your puzzles</h2>
          <p :if={@puzzles == []} class="text-sm text-base-content/60">
            No puzzles yet. Upload a picture to get started.
          </p>
          <ul id="puzzles" class="space-y-2">
            <li
              :for={%{puzzle: p} = row <- @puzzles}
              id={"puzzle-#{p.id}"}
              class="group flex items-center gap-3 rounded-xl border border-base-300 bg-base-100 p-2 pr-3 transition hover:border-primary/50 hover:shadow-sm"
            >
              <.link navigate={~p"/puzzles/#{p}"} class="flex flex-1 items-center gap-3 min-w-0">
                <span class="relative shrink-0">
                  <img
                    :if={cover = List.first(p.images)}
                    src={cover.path}
                    alt=""
                    class="size-14 rounded-lg object-cover bg-base-200"
                  />
                  <span
                    :if={length(p.images) > 1}
                    class="absolute -bottom-1 -right-1 badge badge-xs badge-neutral"
                    title={"#{length(p.images)} pictures"}
                  >
                    ×{length(p.images)}
                  </span>
                </span>
                <div class="min-w-0 flex-1">
                  <p class="font-medium truncate">{p.title}</p>
                  <p class="text-xs text-base-content/60">
                    {pictures(length(p.images))} · {row.glyph_count} glyphs · {row.symbol_count} symbols
                  </p>
                  <div class="mt-1 h-1.5 rounded-full bg-base-200 overflow-hidden">
                    <div
                      class="h-full bg-primary transition-all"
                      style={"width: #{percent(row.solved_count, row.symbol_count)}%"}
                    />
                  </div>
                </div>
              </.link>
              <button
                type="button"
                phx-click="delete"
                phx-value-id={p.id}
                data-confirm={"Delete “#{p.title}”?"}
                class="btn btn-ghost btn-sm btn-square opacity-0 group-hover:opacity-100 focus:opacity-100"
                aria-label={"Delete #{p.title}"}
              >
                <.icon name="hero-trash" class="size-4" />
              </button>
            </li>
          </ul>
        </aside>
      </section>
    </Layouts.app>
    """
  end

  defp pictures(1), do: "1 picture"
  defp pictures(n), do: "#{n} pictures"

  defp percent(_, 0), do: 0
  defp percent(n, total), do: round(n / total * 100)
end
