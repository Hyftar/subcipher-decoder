defmodule SubcipherWeb.PuzzleLive.Index do
  use SubcipherWeb, :live_view

  alias Subcipher.Ciphers
  alias Subcipher.Ciphers.Puzzle
  alias Subcipher.Steps

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Puzzles")
     # The kind of input of the new puzzle: "pictures" or "text".
     |> assign(:input_kind, "pictures")
     |> assign(:first_step, Steps.ciphers() |> hd() |> then(& &1.type()))
     |> assign(:text_form, to_form(Ciphers.change_text_puzzle()))
     |> assign(:puzzles, Ciphers.list_puzzles())}
  end

  @impl true
  def handle_event("set_input_kind", %{"kind" => kind}, socket) when kind in ~w(pictures text) do
    {:noreply, assign(socket, :input_kind, kind)}
  end

  def handle_event("validate_text", %{"puzzle" => params} = all, socket) do
    form = params |> Ciphers.change_text_puzzle() |> Map.put(:action, :validate) |> to_form()

    {:noreply,
     assign(socket, text_form: form, first_step: all["first_step"] || socket.assigns.first_step)}
  end

  def handle_event("create_text", %{"puzzle" => params, "first_step" => first_step}, socket) do
    case Ciphers.create_text_puzzle(params, first_step) do
      {:ok, puzzle} ->
        {:noreply, push_navigate(socket, to: ~p"/puzzles/#{puzzle}")}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, text_form: to_form(changeset), first_step: first_step)}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Could not create the puzzle.")}
    end
  end

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
              Start from pictures of the cipher text (every symbol is detected and identical
              symbols are grouped) or from text. Then decode it step by step, each step taking
              the previous one's output.
            </p>
          </div>

          <div role="tablist" id="input-kind" class="inline-flex rounded-xl bg-base-200 p-1">
            <button
              :for={
                {kind, label, icon} <- [
                  {"pictures", "Pictures", "hero-photo"},
                  {"text", "Text", "hero-document-text"}
                ]
              }
              type="button"
              role="tab"
              id={"input-kind-#{kind}"}
              aria-selected={to_string(@input_kind == kind)}
              phx-click="set_input_kind"
              phx-value-kind={kind}
              class={[
                "flex items-center gap-1.5 rounded-lg px-4 py-1.5 text-sm font-medium transition",
                if(@input_kind == kind,
                  do: "bg-base-100 shadow-sm",
                  else: "text-base-content/60 hover:text-base-content"
                )
              ]}
            >
              <.icon name={icon} class="size-4" /> {label}
            </button>
          </div>

          <.live_component
            :if={@input_kind == "pictures"}
            module={SubcipherWeb.PictureUploadComponent}
            id="new-puzzle"
          />

          <.form
            :if={@input_kind == "text"}
            for={@text_form}
            id="new-text-puzzle-form"
            phx-change="validate_text"
            phx-submit="create_text"
            class="space-y-1"
          >
            <.input
              field={@text_form[:input_text]}
              type="textarea"
              label="Cipher text"
              rows="7"
              placeholder="Paste the cipher text here"
              class="w-full textarea font-mono text-lg leading-relaxed"
            />
            <div class="grid gap-x-3 sm:grid-cols-2">
              <.input field={@text_form[:title]} label="Title" placeholder="Zodiac 408" />
              <.input
                type="select"
                name="first_step"
                id="first-step"
                label="First step"
                value={@first_step}
                options={Enum.map(Steps.ciphers(), &{&1.name(), &1.type()})}
              />
            </div>
            <div class="flex justify-end">
              <.button variant="primary" class="btn btn-primary" phx-disable-with="Creating…">
                Start decoding <.icon name="hero-arrow-right" class="size-4" />
              </.button>
            </div>
          </.form>
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
                  <span
                    :if={!Puzzle.pictures?(p)}
                    class="grid place-items-center size-14 rounded-lg bg-base-200 font-mono text-xs text-base-content/60 overflow-hidden p-1 leading-tight break-all"
                  >
                    {String.slice(p.input_text, 0, 24)}
                  </span>
                  <img
                    :if={cover = Puzzle.pictures?(p) && List.first(p.images)}
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
                    <%= if Puzzle.pictures?(p) do %>
                      {pictures(length(p.images))} · {row.glyph_count} glyphs · {row.symbol_count} symbols
                    <% else %>
                      Text · {String.length(p.input_text)} characters
                    <% end %>
                  </p>
                  <div
                    :if={Puzzle.pictures?(p)}
                    class="mt-1 h-1.5 rounded-full bg-base-200 overflow-hidden"
                  >
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
