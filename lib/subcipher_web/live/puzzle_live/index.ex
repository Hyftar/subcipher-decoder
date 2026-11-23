defmodule SubcipherWeb.PuzzleLive.Index do
  use SubcipherWeb, :live_view

  alias Subcipher.Ciphers
  alias Subcipher.Ciphers.Puzzle
  alias Subcipher.Steps

  import SubcipherWeb.StepComponents, only: [cipher_grid: 1, osrs_usage: 1]

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Puzzles")
     |> assign(:text_form, to_form(Ciphers.change_text_puzzle()))
     |> assign(:puzzles, Ciphers.list_puzzles())
     |> assign(:new_algorithm, false)
     |> assign(:algorithms, Subcipher.Algorithms.list_algorithms())}
  end

  # ?cipher=TYPE: the cipher of the new puzzle (its first step), then the
  # input it needs. ?input=text|pictures picks among the cipher's input
  # kinds (Cipher.input_kinds/0), the first one by default.
  @impl true
  def handle_params(params, _uri, socket) do
    cipher =
      case Steps.fetch_cipher(params["cipher"] || "") do
        {:ok, cipher} -> cipher
        :error -> nil
      end

    kinds = if cipher, do: Enum.map(cipher.input_kinds(), &to_string/1), else: []
    input = if params["input"] in kinds, do: params["input"], else: List.first(kinds)

    {:noreply,
     socket
     |> assign(cipher: cipher, input_kind: input, input_kinds: kinds)
     |> assign(:text_form, to_form(Ciphers.change_text_puzzle()))}
  end

  @impl true
  def handle_event("toggle_new_algorithm", _params, socket) do
    {:noreply, update(socket, :new_algorithm, &(!&1))}
  end

  # A new algorithm opens in its editor.
  def handle_event("create_algorithm", %{"type" => type}, socket) do
    case Subcipher.Algorithms.create_algorithm(type) do
      {:ok, algorithm} ->
        {:noreply, push_navigate(socket, to: ~p"/algorithms/#{algorithm}?edit=true")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "This cipher can't be used in an algorithm.")}
    end
  end

  def handle_event("choose_cipher", %{"type" => type}, socket) do
    {:noreply, push_patch(socket, to: ~p"/?cipher=#{type}")}
  end

  def handle_event("validate_text", %{"puzzle" => params}, socket) do
    form = params |> Ciphers.change_text_puzzle() |> Map.put(:action, :validate) |> to_form()
    {:noreply, assign(socket, :text_form, form)}
  end

  def handle_event("create_text", %{"puzzle" => params}, socket) do
    case Ciphers.create_text_puzzle(params, socket.assigns.cipher.type()) do
      {:ok, puzzle} ->
        {:noreply, push_navigate(socket, to: ~p"/puzzles/#{puzzle}")}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, :text_form, to_form(changeset))}

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
            <h1 class="text-2xl font-bold tracking-tight">Crack a cipher</h1>
            <p class="text-base-content/70 mt-1">
              Choose the cipher, give it the cipher text (or pictures of its symbols), then
              decode it step by step: more steps can be added, each taking the previous one's
              output.
            </p>
          </div>

          <div :if={!@cipher} id="choose-cipher" class="space-y-3">
            <h2 class="font-semibold">Which cipher is it?</h2>
            <.cipher_grid id_prefix="new-cipher-" event="choose_cipher" />
          </div>

          <div :if={@cipher} id="new-puzzle-input" class="space-y-4">
            <div class="flex items-start gap-3 rounded-xl border border-primary/40 bg-primary/5 p-4">
              <div class="flex-1 min-w-0 space-y-1">
                <p class="font-semibold">{@cipher.name()}</p>
                <p class="text-sm text-base-content/60">{@cipher.description()}</p>
                <.osrs_usage cipher={@cipher} />
              </div>
              <.link patch={~p"/"} id="change-cipher" class="btn btn-ghost btn-sm shrink-0">
                <.icon name="hero-arrow-path-rounded-square" class="size-4" /> Change
              </.link>
            </div>

            <%= if @input_kind == "pictures" do %>
              <.live_component module={SubcipherWeb.PictureUploadComponent} id="new-puzzle" />
            <% else %>
              <.form
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
                  placeholder={placeholder(@cipher)}
                  class="w-full textarea font-mono text-lg leading-relaxed"
                />
                <div class="flex flex-col sm:flex-row gap-3 sm:items-end">
                  <div class="flex-1">
                    <.input field={@text_form[:title]} label="Title" placeholder="Zodiac 408" />
                  </div>
                  <.button
                    variant="primary"
                    class="btn btn-primary mb-2"
                    phx-disable-with="Creating…"
                  >
                    Start decoding <.icon name="hero-arrow-right" class="size-4" />
                  </.button>
                </div>
              </.form>
            <% end %>

            <p :if={length(@input_kinds) > 1} class="text-sm text-base-content/60">
              <%= for kind <- @input_kinds, kind != @input_kind do %>
                <.link
                  patch={~p"/?cipher=#{@cipher.type()}&input=#{kind}"}
                  id={"use-input-#{kind}"}
                  class="link link-hover inline-flex items-center gap-1"
                >
                  <.icon name={input_icon(kind)} class="size-4" /> {input_switch_label(kind)}
                </.link>
              <% end %>
            </p>
          </div>
        </div>

        <aside class="space-y-3">
          <h2 class="font-semibold text-base-content/80">Your puzzles</h2>
          <p :if={@puzzles == []} class="text-sm text-base-content/60">
            No puzzles yet. Choose a cipher to get started.
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

          <div class="flex items-center justify-between gap-2 pt-4">
            <h2 class="font-semibold text-base-content/80">Your algorithms</h2>
            <button
              type="button"
              id="new-algorithm"
              class={["btn btn-sm", if(@new_algorithm, do: "btn-active", else: "btn-ghost")]}
              phx-click="toggle_new_algorithm"
              aria-expanded={to_string(@new_algorithm)}
            >
              <.icon name="hero-plus" class="size-4" /> New
            </button>
          </div>
          <div :if={@new_algorithm} id="new-algorithm-panel" class="space-y-2">
            <p class="text-sm text-base-content/60">
              Its first step (more can be added after):
            </p>
            <.cipher_grid
              id_prefix="new-algorithm-"
              event="create_algorithm"
              icon="hero-plus-circle"
              class="grid-cols-1"
              ciphers={Subcipher.Algorithms.ciphers()}
            />
          </div>
          <p :if={@algorithms == [] and !@new_algorithm} class="text-sm text-base-content/60">
            None yet: create one with <strong>New</strong>, or on a puzzle, "Make an algorithm"
            turns its steps into one, to encode and decode any text.
          </p>
          <ul id="algorithms" class="space-y-2">
            <li :for={algorithm <- @algorithms} id={"algorithm-#{algorithm.id}"}>
              <.link
                navigate={~p"/algorithms/#{algorithm}"}
                class="flex items-center gap-3 rounded-xl border border-base-300 bg-base-100 p-2 pr-3 transition hover:border-primary/50 hover:shadow-sm"
              >
                <span class="grid place-items-center size-10 rounded-lg bg-primary/10 text-primary shrink-0">
                  <.icon name="hero-cog-6-tooth" class="size-5" />
                </span>
                <span class="min-w-0">
                  <span class="block font-medium truncate">{algorithm.title}</span>
                  <span class="block text-xs text-base-content/60">
                    {algorithm_steps(algorithm)}
                  </span>
                </span>
              </.link>
            </li>
          </ul>
        </aside>
      </section>
    </Layouts.app>
    """
  end

  defp placeholder(cipher) do
    case cipher.type() do
      "morse" -> "-- --- .-. ... . / -.-. --- -.. ."
      "letter_numbers" -> "8 5 12 12 15 | 23 15 18 12 4"
      "symbol_substitution" -> "☀♪Θ ♠Φ☎Θ"
      _ -> "Paste the cipher text here"
    end
  end

  defp input_icon("pictures"), do: "hero-photo"
  defp input_icon(_), do: "hero-document-text"

  defp input_switch_label("pictures"), do: "Upload pictures instead"
  defp input_switch_label(_), do: "Have it as text? Paste it instead"

  defp algorithm_steps(algorithm) do
    names = Enum.map(algorithm.steps, &Steps.cipher!(&1["type"]).name())

    names =
      if algorithm.input_kind == "pictures", do: ["Symbol substitution" | names], else: names

    Enum.join(names, " → ")
  end

  defp pictures(1), do: "1 picture"
  defp pictures(n), do: "#{n} pictures"

  defp percent(_, 0), do: 0
  defp percent(n, total), do: round(n / total * 100)
end
