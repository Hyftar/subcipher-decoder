defmodule SubcipherWeb.PuzzleLive.Show do
  use SubcipherWeb, :live_view

  alias Subcipher.Ciphers

  # Height (px) at which the typical glyph is displayed in the cipher text.
  @display_height 40
  @english_frequency "ETAOINSHRDLCUMWFGYPBVKJXQZ"

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    puzzle = Ciphers.get_puzzle!(id)

    {:ok,
     socket
     |> assign(:page_title, puzzle.title)
     |> assign(:selected_symbol_id, nil)
     |> assign(:selected_glyph_id, nil)
     |> assign(:merging, false)
     |> assign(:show_image, false)
     |> assign(:english_frequency, @english_frequency)
     |> load(puzzle)}
  end

  ## Loading & derived state

  defp reload(socket), do: load(socket, Ciphers.get_puzzle!(socket.assigns.puzzle.id))

  defp load(socket, puzzle) do
    symbols = Map.new(puzzle.symbols, &{&1.id, &1})
    by_symbol = Enum.group_by(puzzle.glyphs, & &1.symbol_id)
    visible = Enum.reject(puzzle.glyphs, &symbols[&1.symbol_id].ignored)
    total = max(length(visible), 1)

    key =
      puzzle.symbols
      |> Enum.map(fn s ->
        glyphs = Map.get(by_symbol, s.id, [])

        %{
          symbol: s,
          sample: List.first(glyphs),
          count: length(glyphs),
          frequency: if(s.ignored, do: 0.0, else: length(glyphs) / total * 100)
        }
      end)
      |> Enum.reject(&is_nil(&1.sample))
      |> Enum.sort_by(&{&1.symbol.ignored, -&1.count, &1.sample.position})

    duplicates =
      puzzle.symbols
      |> Enum.reject(&(&1.ignored or is_nil(&1.letter)))
      |> Enum.frequencies_by(& &1.letter)
      |> Enum.filter(fn {_, n} -> n > 1 end)
      |> MapSet.new(fn {l, _} -> l end)

    active = Enum.reject(key, & &1.symbol.ignored)

    socket
    |> assign(:puzzle, puzzle)
    |> assign(:title_form, to_form(Ciphers.change_title(puzzle)))
    |> assign(:symbols, symbols)
    |> assign(:key, key)
    |> assign(:lines, lines(puzzle.glyphs))
    |> assign(:scale, @display_height / max(median(Enum.map(puzzle.glyphs, & &1.h)), 1))
    |> assign(:duplicates, duplicates)
    |> assign(:solved, Enum.count(active, & &1.symbol.letter))
    |> assign(:symbol_count, length(active))
    |> assign(:plaintext, Ciphers.plaintext(puzzle))
    |> assign(:tolerance, round(puzzle.threshold * 1000))
    |> keep_selection_valid()
  end

  # Lines -> words -> glyphs, with each line's vertical extent so glyphs can
  # keep their position relative to the baseline.
  defp lines(glyphs) do
    glyphs
    |> Enum.chunk_by(& &1.line)
    |> Enum.map(fn line ->
      top = line |> Enum.map(& &1.y) |> Enum.min()
      bottom = line |> Enum.map(&(&1.y + &1.h)) |> Enum.max()

      words =
        Enum.chunk_while(
          line,
          [],
          fn g, acc ->
            if g.space_before and acc != [],
              do: {:cont, Enum.reverse(acc), [g]},
              else: {:cont, [g | acc]}
          end,
          fn acc -> {:cont, Enum.reverse(acc), []} end
        )

      %{id: hd(line).line, top: top, height: bottom - top, words: words}
    end)
  end

  defp keep_selection_valid(socket) do
    %{symbols: symbols, puzzle: puzzle} = socket.assigns

    socket =
      if Map.has_key?(symbols, socket.assigns.selected_symbol_id),
        do: socket,
        else: assign(socket, selected_symbol_id: nil, merging: false)

    glyph = Enum.find(puzzle.glyphs, &(&1.id == socket.assigns.selected_glyph_id))

    if glyph && glyph.symbol_id == socket.assigns.selected_symbol_id,
      do: socket,
      else: assign(socket, :selected_glyph_id, nil)
  end

  defp median([]), do: 0
  defp median(values), do: values |> Enum.sort() |> Enum.at(div(length(values), 2))

  ## Events

  @impl true
  def handle_event("select_glyph", %{"id" => id}, socket) do
    case Enum.find(socket.assigns.puzzle.glyphs, &(to_string(&1.id) == id)) do
      nil -> {:noreply, socket}
      glyph -> {:noreply, select(socket, glyph.symbol_id, glyph.id)}
    end
  end

  def handle_event("select_symbol", %{"id" => id}, socket) do
    case Enum.find(socket.assigns.puzzle.symbols, &(to_string(&1.id) == id)) do
      nil -> {:noreply, socket}
      symbol -> {:noreply, select(socket, symbol.id, nil)}
    end
  end

  def handle_event("deselect", _params, socket) do
    {:noreply, assign(socket, selected_symbol_id: nil, selected_glyph_id: nil, merging: false)}
  end

  def handle_event("key", %{"key" => key} = params, socket) do
    handle_key(key, params["shift"] == true, socket)
  end

  def handle_event("assign", %{"symbol_id" => id, "letter" => letter}, socket) do
    case socket.assigns.symbols[String.to_integer(id)] do
      nil -> {:noreply, socket}
      symbol -> {:noreply, assign_letter(socket, symbol, letter)}
    end
  end

  def handle_event("toggle_ignore", %{"id" => id}, socket) do
    symbol = Map.fetch!(socket.assigns.symbols, String.to_integer(id))
    {:ok, _} = Ciphers.set_ignored(symbol, !symbol.ignored)
    {:noreply, reload(socket)}
  end

  def handle_event("start_merge", _params, socket) do
    {:noreply, assign(socket, :merging, socket.assigns.selected_symbol_id != nil)}
  end

  def handle_event("cancel_merge", _params, socket) do
    {:noreply, assign(socket, :merging, false)}
  end

  def handle_event("detach", _params, socket) do
    glyph = Enum.find(socket.assigns.puzzle.glyphs, &(&1.id == socket.assigns.selected_glyph_id))

    case glyph && Ciphers.detach_glyph(glyph) do
      {:ok, symbol} ->
        {:noreply,
         socket
         |> assign(selected_symbol_id: symbol.id)
         |> put_flash(:info, "This glyph is now a symbol of its own.")
         |> reload()}

      _ ->
        {:noreply, socket}
    end
  end

  def handle_event("reset_letters", _params, socket) do
    :ok = Ciphers.reset_letters(socket.assigns.puzzle)
    {:noreply, reload(socket)}
  end

  def handle_event("toggle_image", _params, socket) do
    {:noreply, update(socket, :show_image, &(!&1))}
  end

  def handle_event("regroup", %{"tolerance" => tolerance}, socket) do
    with {t, ""} <- Integer.parse(tolerance),
         true <- t in 5..150,
         {:ok, puzzle} <- Ciphers.regroup(socket.assigns.puzzle, t / 1000) do
      {:noreply,
       socket
       |> assign(selected_symbol_id: nil, selected_glyph_id: nil, merging: false)
       |> load(puzzle)
       |> put_flash(:info, "Symbols regrouped: #{length(puzzle.symbols)} distinct symbols.")}
    else
      _ -> {:noreply, put_flash(socket, :error, "Could not regroup the symbols.")}
    end
  end

  def handle_event("rename_blur", %{"value" => title}, socket) do
    if title == socket.assigns.puzzle.title,
      do: {:noreply, socket},
      else: handle_event("rename", %{"puzzle" => %{"title" => title}}, socket)
  end

  def handle_event("rename", %{"puzzle" => params}, socket) do
    case Ciphers.update_title(socket.assigns.puzzle, params) do
      {:ok, puzzle} ->
        {:noreply,
         socket
         |> assign(:page_title, puzzle.title)
         |> reload()}

      {:error, changeset} ->
        {:noreply, assign(socket, :title_form, to_form(changeset))}
    end
  end

  # Clicking a symbol while merging merges it into the selected symbol.
  defp select(%{assigns: %{merging: true}} = socket, symbol_id, _glyph_id) do
    %{selected_symbol_id: target_id, symbols: symbols} = socket.assigns

    if symbol_id == target_id do
      assign(socket, :merging, false)
    else
      {:ok, _} = Ciphers.merge_symbols(symbols[target_id], symbols[symbol_id])

      socket
      |> assign(:merging, false)
      |> put_flash(:info, "Symbols merged.")
      |> reload()
    end
  end

  defp select(socket, symbol_id, glyph_id) do
    assign(socket, selected_symbol_id: symbol_id, selected_glyph_id: glyph_id)
  end

  defp handle_key("Escape", _shift, socket) do
    if socket.assigns.merging,
      do: {:noreply, assign(socket, :merging, false)},
      else: {:noreply, assign(socket, selected_symbol_id: nil, selected_glyph_id: nil)}
  end

  defp handle_key(key, shift, socket)
       when key in ~w(ArrowRight ArrowDown Tab ArrowLeft ArrowUp) do
    backwards = key in ~w(ArrowLeft ArrowUp) or (key == "Tab" and shift)
    {:noreply, move_selection(socket, if(backwards, do: -1, else: 1))}
  end

  defp handle_key(key, _shift, socket) when key in ~w(Backspace Delete) do
    case selected_symbol(socket) do
      nil -> {:noreply, socket}
      symbol -> {:noreply, assign_letter(socket, symbol, nil)}
    end
  end

  defp handle_key(key, _shift, socket) do
    case {selected_symbol(socket), String.length(key)} do
      {%{} = symbol, 1} -> {:noreply, assign_letter(socket, symbol, key)}
      _ -> {:noreply, socket}
    end
  end

  defp selected_symbol(socket), do: socket.assigns.symbols[socket.assigns.selected_symbol_id]

  # Moves through the symbol key (most frequent first), skipping ignored ones.
  defp move_selection(socket, step) do
    ids = for %{symbol: s} <- socket.assigns.key, !s.ignored, do: s.id

    case ids do
      [] ->
        socket

      ids ->
        index = Enum.find_index(ids, &(&1 == socket.assigns.selected_symbol_id))

        next =
          case index do
            nil -> if step > 0, do: 0, else: -1
            i -> rem(i + step + length(ids), length(ids))
          end

        assign(socket, selected_symbol_id: Enum.at(ids, next), selected_glyph_id: nil)
    end
  end

  defp assign_letter(socket, symbol, letter) do
    case Ciphers.assign_letter(symbol, letter) do
      {:ok, _} -> reload(socket)
      {:error, _} -> put_flash(socket, :error, "A substitution is at most 3 characters.")
    end
  end

  ## Rendering

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <div
        id="puzzle"
        phx-hook="CipherKeys"
        data-selected={to_string(@selected_symbol_id != nil)}
        class="space-y-6"
      >
        <div class="flex flex-wrap items-center gap-3">
          <.link navigate={~p"/"} class="btn btn-ghost btn-sm btn-square" aria-label="Back">
            <.icon name="hero-arrow-left" class="size-5" />
          </.link>
          <.form
            for={@title_form}
            id="title-form"
            phx-submit="rename"
            class="flex-1 min-w-48"
          >
            <input
              type="text"
              name={@title_form[:title].name}
              value={@title_form[:title].value}
              phx-blur="rename_blur"
              aria-label="Title"
              class="w-full bg-transparent text-2xl font-bold tracking-tight rounded-md px-1 -mx-1 focus:outline-none focus:ring-2 focus:ring-primary/40"
            />
          </.form>
          <div class="flex items-center gap-3 text-sm">
            <span class="text-base-content/70" id="progress">
              {@solved} / {@symbol_count} symbols
            </span>
            <progress class="progress progress-primary w-32" value={@solved} max={@symbol_count} />
          </div>
        </div>

        <div class="grid gap-6 lg:grid-cols-[minmax(0,1fr)_20rem]">
          <div class="space-y-6 min-w-0">
            <.selection_bar
              symbol={@symbols[@selected_symbol_id]}
              glyph_id={@selected_glyph_id}
              merging={@merging}
              key={@key}
              puzzle={@puzzle}
            />

            <section
              id="cipher-text"
              class="rounded-2xl border border-base-300 bg-base-100 p-4 sm:p-6 space-y-5 overflow-x-auto"
              phx-click="deselect"
            >
              <div
                :for={line <- @lines}
                id={"line-#{line.id}"}
                class="flex flex-wrap gap-x-5 gap-y-3 pb-5 border-b border-dashed border-base-300 last:border-0 last:pb-0"
              >
                <div :for={word <- line.words} class="flex items-start gap-1">
                  <.glyph_cell
                    :for={g <- word}
                    glyph={g}
                    line={line}
                    symbol={@symbols[g.symbol_id]}
                    puzzle={@puzzle}
                    scale={@scale}
                    selected={g.symbol_id == @selected_symbol_id}
                    current={g.id == @selected_glyph_id}
                    merging={@merging}
                    duplicate={MapSet.member?(@duplicates, @symbols[g.symbol_id].letter)}
                  />
                </div>
              </div>
            </section>

            <section class="rounded-2xl border border-base-300 bg-base-100">
              <div class="flex items-center justify-between px-4 py-2 border-b border-base-300">
                <h2 class="font-semibold text-sm">Deciphered text</h2>
                <button
                  type="button"
                  class="btn btn-ghost btn-xs"
                  phx-click={JS.dispatch("phx:copy", to: "#plaintext")}
                  id="copy-plaintext"
                >
                  <.icon name="hero-clipboard" class="size-4" /> Copy
                </button>
              </div>
              <pre
                id="plaintext"
                class="p-4 font-mono text-lg whitespace-pre-wrap break-words leading-relaxed tracking-wider"
              >{@plaintext}</pre>
            </section>

            <section class="rounded-2xl border border-base-300 bg-base-100">
              <button
                type="button"
                phx-click="toggle_image"
                class="w-full flex items-center justify-between px-4 py-2 text-sm font-semibold"
              >
                Original picture & detected symbols
                <.icon
                  name={if @show_image, do: "hero-chevron-up", else: "hero-chevron-down"}
                  class="size-4"
                />
              </button>
              <div :if={@show_image} class="p-4 pt-0">
                <div class="relative">
                  <img
                    src={@puzzle.image_path}
                    alt="Cipher picture"
                    class="block w-full h-auto rounded-lg"
                  />
                  <button
                    :for={g <- @puzzle.glyphs}
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
                    style={box_style(g, @puzzle)}
                  />
                </div>
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
                    class="btn btn-sm"
                    data-confirm="Regroup all symbols? Letters are kept when all glyphs of a new group agree."
                  >
                    Regroup symbols
                  </button>
                </.form>
              </div>
            </section>
          </div>

          <.symbol_key
            key={@key}
            puzzle={@puzzle}
            selected_symbol_id={@selected_symbol_id}
            duplicates={@duplicates}
            english_frequency={@english_frequency}
          />
        </div>
      </div>
    </Layouts.app>
    """
  end

  attr :symbol, :any, required: true
  attr :glyph_id, :any, required: true
  attr :merging, :boolean, required: true
  attr :key, :list, required: true
  attr :puzzle, :any, required: true

  defp selection_bar(%{symbol: nil} = assigns) do
    ~H"""
    <div class="rounded-xl bg-base-200/60 px-4 py-3 text-sm text-base-content/70 flex items-center gap-2">
      <.icon name="hero-cursor-arrow-rays" class="size-5 shrink-0" />
      Click a symbol, then type the letter it stands for. Every identical symbol is replaced
      at once. <kbd class="kbd kbd-xs">←</kbd><kbd class="kbd kbd-xs">→</kbd>
      move between symbols, <kbd class="kbd kbd-xs">⌫</kbd>
      clears.
    </div>
    """
  end

  defp selection_bar(assigns) do
    assigns =
      assign(assigns, :entry, Enum.find(assigns.key, &(&1.symbol.id == assigns.symbol.id)))

    ~H"""
    <div
      id="selection-bar"
      class={[
        "rounded-xl px-4 py-3 flex flex-wrap items-center gap-3 text-sm transition-colors",
        if(@merging, do: "bg-warning/15 ring-1 ring-warning", else: "bg-primary/10")
      ]}
    >
      <span class="grid place-items-center size-12 rounded-lg bg-base-100 shrink-0">
        <.glyph_image glyph={@entry.sample} puzzle={@puzzle} box={40} />
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
          <button type="button" class="btn btn-sm" phx-click="cancel_merge">Cancel</button>
        <% else %>
          <button type="button" class="btn btn-sm" phx-click="start_merge" id="merge-button">
            <.icon name="hero-arrows-pointing-in" class="size-4" /> Merge…
          </button>
          <button
            :if={@glyph_id && @entry.count > 1}
            type="button"
            class="btn btn-sm"
            phx-click="detach"
            id="detach-button"
            title="This occurrence is actually a different symbol"
          >
            <.icon name="hero-scissors" class="size-4" /> Split this one off
          </button>
          <button
            type="button"
            class="btn btn-sm"
            phx-click="toggle_ignore"
            phx-value-id={@symbol.id}
            title="Hide noise or decorations from the text"
          >
            <.icon name={if @symbol.ignored, do: "hero-eye", else: "hero-eye-slash"} class="size-4" />
            {if @symbol.ignored, do: "Restore", else: "Ignore"}
          </button>
        <% end %>
      </div>
    </div>
    """
  end

  attr :glyph, :any, required: true
  attr :line, :map, required: true
  attr :symbol, :any, required: true
  attr :puzzle, :any, required: true
  attr :scale, :float, required: true
  attr :selected, :boolean, required: true
  attr :current, :boolean, required: true
  attr :merging, :boolean, required: true
  attr :duplicate, :boolean, required: true

  defp glyph_cell(assigns) do
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
          <.glyph_image glyph={@glyph} puzzle={@puzzle} scale={@scale} />
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

  attr :key, :list, required: true
  attr :puzzle, :any, required: true
  attr :selected_symbol_id, :any, required: true
  attr :duplicates, :any, required: true
  attr :english_frequency, :string, required: true

  defp symbol_key(assigns) do
    ~H"""
    <aside class="space-y-3 lg:sticky lg:top-20 lg:self-start">
      <div class="flex items-center justify-between">
        <h2 class="font-semibold">Symbol key</h2>
        <button
          type="button"
          class="btn btn-ghost btn-xs"
          phx-click="reset_letters"
          data-confirm="Clear every letter?"
        >
          <.icon name="hero-arrow-path" class="size-4" /> Reset
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
              <.glyph_image glyph={entry.sample} puzzle={@puzzle} box={32} />
            </span>
            <span class="text-xs text-base-content/70 leading-tight">
              <span class="block font-medium text-base-content">×{entry.count}</span>
              {if entry.symbol.ignored, do: "ignored", else: "#{Float.round(entry.frequency, 1)}%"}
            </span>
          </button>
          <form
            :if={!entry.symbol.ignored}
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

  attr :glyph, :any, required: true
  attr :puzzle, :any, required: true
  attr :scale, :float, default: nil, doc: "explicit display scale"
  attr :box, :integer, default: nil, doc: "fit the glyph in a square of this size (px)"

  # Renders a glyph by cropping the original picture with CSS.
  defp glyph_image(assigns) do
    %{glyph: g, puzzle: p} = assigns
    pad = 2
    w = g.w + 2 * pad
    h = g.h + 2 * pad
    scale = assigns.scale || assigns.box / max(w, h)

    style =
      [
        "width: #{px(w * scale)}",
        "height: #{px(h * scale)}",
        "background-image: url('#{p.image_path}')",
        "background-size: #{px(p.image_width * scale)} #{px(p.image_height * scale)}",
        "background-position: #{px(-(g.x - pad) * scale)} #{px(-(g.y - pad) * scale)}"
      ]
      |> Enum.join("; ")

    assigns = assign(assigns, :style, style)

    ~H"""
    <span class="block bg-no-repeat rounded-sm" style={@style} aria-hidden="true"></span>
    """
  end

  defp px(v), do: "#{Float.round(v * 1.0, 2)}px"

  defp box_style(g, p) do
    "left: #{g.x / p.image_width * 100}%; top: #{g.y / p.image_height * 100}%; " <>
      "width: #{g.w / p.image_width * 100}%; height: #{g.h / p.image_height * 100}%"
  end
end
