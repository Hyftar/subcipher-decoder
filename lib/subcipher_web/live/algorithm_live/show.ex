defmodule SubcipherWeb.AlgorithmLive.Show do
  @moduledoc """
  An algorithm (a frozen puzzle): encode or decode any text with its steps,
  showing the text after each step.
  """
  use SubcipherWeb, :live_view

  alias Subcipher.{Algorithms, Steps}
  alias Subcipher.Algorithms.Algorithm
  alias Subcipher.Steps.Step

  import SubcipherWeb.StepComponents, only: [output: 1]

  # Height (px) of the symbols drawn from the symbol key.
  @symbol_height 36

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    case Algorithms.get_algorithm(id) do
      nil ->
        {:ok,
         socket
         |> put_flash(:error, "This algorithm doesn't exist anymore.")
         |> push_navigate(to: ~p"/")}

      algorithm ->
        {:ok, init(socket, algorithm)}
    end
  end

  defp init(socket, algorithm) do
    socket
    |> assign(:page_title, algorithm.title)
    |> assign(:algorithm, algorithm)
    |> assign(:steps, describe_steps(algorithm))
    |> assign(:mode, "encode")
    # What the user typed, per mode (kept when switching).
    |> assign(:texts, %{"encode" => "", "decode" => ""})
    # Pictures, decode: the symbols composed with the keyboard.
    |> assign(:symbols, [])
    # Pictures, encode: the composed image's options. Its style is "original"
    # (the crops as they are) or "mask" (their black and white pass, in the
    # ink colour); colours are "auto" (detected in the glyphs, reported by
    # the SymbolImage hook) or chosen by hand.
    |> assign(:image, %{
      style: "original",
      align: "center",
      background: "auto",
      ink: "auto",
      transparent: false
    })
    |> assign(:detected, %{background: nil, ink: nil})
  end

  @impl true
  def handle_params(params, _uri, socket) do
    mode = if params["mode"] in ~w(encode decode), do: params["mode"], else: "encode"
    {:noreply, socket |> assign(:mode, mode) |> assign_trace()}
  end

  # The frozen steps, for display: number, cipher name and its settings.
  defp describe_steps(algorithm) do
    pictures =
      if Algorithm.pictures?(algorithm),
        do: [
          %{
            number: 1,
            name: "Symbol substitution",
            settings: "#{length(algorithm.symbol_key)} symbols in the key"
          }
        ],
        else: []

    offset = length(pictures) + 1

    steps =
      for {%{"type" => type, "params" => params}, number} <-
            Enum.with_index(algorithm.steps, offset) do
        cipher = Steps.cipher!(type)
        params = Steps.params(%Step{type: type, params: params})

        settings =
          if Steps.implements?(cipher, :summary, 1) && cipher.summary(params),
            do: cipher.summary(params),
            else: settings_text(cipher, params)

        %{number: number, name: cipher.name(), settings: settings}
      end

    pictures ++ steps
  end

  defp settings_text(cipher, params) do
    cipher.fields()
    |> Enum.map(fn field ->
      value =
        case Map.get(params, field.name) do
          map when is_map(map) -> "#{map_size(map)} substitutions"
          nil -> "automatic"
          "" -> "none"
          value -> to_string(value)
        end

      "#{field.label}: #{value}"
    end)
    |> Enum.join(" · ")
    |> case do
      "" -> "No settings"
      text -> text
    end
  end

  defp assign_trace(socket) do
    %{algorithm: algorithm, mode: mode, texts: texts, symbols: symbols} = socket.assigns

    trace =
      case mode do
        "encode" ->
          Algorithms.encode(algorithm, texts["encode"])

        "decode" ->
          if Algorithm.pictures?(algorithm),
            do: Algorithms.decode(algorithm, symbols),
            else: Algorithms.decode(algorithm, texts["decode"])
      end

    assign(socket, :trace, trace)
  end

  @impl true
  def handle_event("input", %{"text" => text}, socket) do
    {:noreply,
     socket
     |> update(:texts, &Map.put(&1, socket.assigns.mode, text))
     |> assign_trace()}
  end

  def handle_event("add_symbol", %{"index" => index}, socket) do
    {:noreply, add_token(socket, {:symbol, String.to_integer(index)})}
  end

  # Whitespace keys send a name: raw whitespace doesn't survive HTML
  # attributes reliably (a "\n" in a ~H template stays a backslash and an n).
  def handle_event("add_char", %{"char" => "space"}, socket),
    do: {:noreply, add_token(socket, {:char, " "})}

  def handle_event("add_char", %{"char" => "newline"}, socket),
    do: {:noreply, add_token(socket, {:char, "\n"})}

  def handle_event("add_char", _params, socket), do: {:noreply, socket}

  def handle_event("backspace", _params, socket) do
    {:noreply, socket |> update(:symbols, &Enum.drop(&1, -1)) |> assign_trace()}
  end

  def handle_event("clear", _params, socket) do
    {:noreply, socket |> assign(:symbols, []) |> assign_trace()}
  end

  # The colour inputs of the image options: only the one changed (`_target`)
  # is taken, so the other stays "auto" (detected).
  def handle_event("image_options", %{"_target" => [field]} = params, socket)
      when field in ~w(background ink) do
    case params[field] do
      "#" <> hex = colour when byte_size(hex) == 6 ->
        {:noreply, update_image(socket, String.to_existing_atom(field), String.downcase(colour))}

      _ ->
        {:noreply, socket}
    end
  end

  def handle_event("image_options", _params, socket), do: {:noreply, socket}

  def handle_event("image_align", %{"align" => align}, socket)
      when align in ~w(left center right),
      do: {:noreply, update_image(socket, :align, align)}

  def handle_event("image_style", %{"style" => style}, socket)
      when style in ~w(original mask),
      do: {:noreply, update_image(socket, :style, style)}

  def handle_event("image_auto", %{"colour" => field}, socket)
      when field in ~w(background ink),
      do: {:noreply, update_image(socket, String.to_existing_atom(field), "auto")}

  def handle_event("image_transparent", _params, socket),
    do: {:noreply, update_image(socket, :transparent, !socket.assigns.image.transparent)}

  def handle_event("detected_colours", colours, socket) do
    detected =
      Map.new(~w(background ink)a, fn key ->
        {key, valid_colour(colours[Atom.to_string(key)]) || socket.assigns.detected[key]}
      end)

    {:noreply, assign(socket, :detected, detected)}
  end

  def handle_event("delete", _params, socket) do
    {:ok, _} = Algorithms.delete_algorithm(socket.assigns.algorithm)

    {:noreply,
     socket
     |> put_flash(:info, "Algorithm deleted.")
     |> push_navigate(to: ~p"/")}
  end

  defp update_image(socket, key, value), do: update(socket, :image, &Map.put(&1, key, value))

  defp valid_colour("#" <> hex = colour) when byte_size(hex) == 6 do
    if hex =~ ~r/^[0-9a-fA-F]{6}$/, do: String.downcase(colour)
  end

  defp valid_colour(_), do: nil

  defp add_token(socket, token) do
    socket |> update(:symbols, &(&1 ++ [token])) |> assign_trace()
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <div id="algorithm" class="space-y-6">
        <div class="flex flex-wrap items-center gap-3">
          <.link navigate={~p"/"} class="btn btn-ghost btn-sm btn-square" aria-label="Back">
            <.icon name="hero-arrow-left" class="size-5" />
          </.link>
          <div class="flex-1 min-w-48">
            <p class="text-xs font-semibold uppercase tracking-wider text-primary">Algorithm</p>
            <h1 class="text-2xl font-bold tracking-tight">{@algorithm.title}</h1>
          </div>
          <.link
            :if={@algorithm.source_puzzle_id}
            navigate={~p"/puzzles/#{@algorithm.source_puzzle_id}"}
            class="btn btn-ghost btn-sm"
            id="source-puzzle"
          >
            <.icon name="hero-puzzle-piece" class="size-4" /> Puzzle
          </.link>
          <button
            type="button"
            id="delete-algorithm"
            class="btn btn-ghost btn-sm"
            phx-click="delete"
            data-confirm="Delete this algorithm?"
          >
            <.icon name="hero-trash" class="size-4" /> Delete
          </button>
        </div>

        <section
          id="algorithm-steps"
          class="rounded-2xl border border-base-300 bg-base-100 p-4 sm:p-6 space-y-3"
        >
          <h2 class="flex items-center gap-2 text-xs font-semibold uppercase tracking-wider text-base-content/50">
            <.icon name="hero-lock-closed" class="size-4" /> Steps (fixed)
          </h2>
          <ol class="flex flex-wrap items-stretch gap-2">
            <li
              :for={{step, i} <- Enum.with_index(@steps)}
              id={"algorithm-step-#{step.number}"}
              class="flex items-center gap-2"
            >
              <span
                :if={i > 0}
                class="text-base-content/30"
                aria-hidden="true"
              >
                <.icon name="hero-chevron-right" class="size-4" />
              </span>
              <span class="rounded-xl border border-base-300 px-3 py-2">
                <span class="flex items-center gap-2 text-sm font-semibold">
                  <span class="grid place-items-center size-5 rounded-full bg-base-200 text-xs">
                    {step.number}
                  </span>
                  {step.name}
                </span>
                <span class="block mt-0.5 font-mono text-xs text-base-content/60 whitespace-pre-line">
                  {step.settings}
                </span>
              </span>
            </li>
          </ol>
        </section>

        <div
          role="tablist"
          id="mode-switch"
          class="inline-flex rounded-xl bg-base-200 p-1"
        >
          <.link
            :for={
              {mode, label, icon} <- [
                {"encode", "Encode", "hero-lock-closed"},
                {"decode", "Decode", "hero-lock-open"}
              ]
            }
            patch={~p"/algorithms/#{@algorithm}?mode=#{mode}"}
            role="tab"
            id={"mode-#{mode}"}
            aria-selected={to_string(@mode == mode)}
            class={[
              "flex items-center gap-1.5 rounded-lg px-4 py-1.5 text-sm font-medium transition",
              if(@mode == mode,
                do: "bg-base-100 shadow-sm",
                else: "text-base-content/60 hover:text-base-content"
              )
            ]}
          >
            <.icon name={icon} class="size-4" /> {label}
          </.link>
        </div>

        <section id="algorithm-input" class="space-y-2">
          <%= if @mode == "decode" and Algorithm.pictures?(@algorithm) do %>
            <.symbol_keyboard algorithm={@algorithm} symbols={@symbols} />
          <% else %>
            <.form for={%{}} id="text-form" phx-change="input" phx-submit="input">
              <label for="algorithm-text" class="block text-sm font-medium mb-1">
                {if @mode == "encode", do: "Plain text to encode", else: "Cipher text to decode"}
              </label>
              <textarea
                id="algorithm-text"
                name="text"
                rows="4"
                phx-debounce="250"
                spellcheck="false"
                placeholder={
                  if @mode == "encode", do: "Type a message", else: "Paste the cipher text"
                }
                class="w-full rounded-lg border border-base-300 bg-base-200/50 p-3 font-mono text-lg leading-relaxed tracking-wider focus:outline-none focus:ring-2 focus:ring-primary/40"
              >{Phoenix.HTML.Form.normalize_value("textarea", @texts[@mode])}</textarea>
            </.form>
          <% end %>
        </section>

        <section id="trace" class="space-y-2">
          <h2 class="text-xs font-semibold uppercase tracking-wider text-base-content/50">
            {if @mode == "encode", do: "Encoding, step by step", else: "Decoding, step by step"}
          </h2>
          <ol class="space-y-0">
            <li :for={{stage, i} <- Enum.with_index(@trace)} id={"stage-#{i}"}>
              <div
                :if={i > 0}
                class="flex justify-center py-1 text-base-content/30"
                aria-hidden="true"
              >
                <.icon name="hero-arrow-down" class="size-4" />
              </div>
              <div class={[
                "rounded-xl border p-3 space-y-2",
                if(i == length(@trace) - 1,
                  do: "border-primary/50 bg-primary/5",
                  else: "border-base-300 bg-base-100"
                )
              ]}>
                <p class="text-xs font-semibold uppercase tracking-wider text-base-content/60">
                  {stage.label}
                </p>
                <%= cond do %>
                  <% stage.kind == :symbols and @mode == "encode" -> %>
                    <.symbol_image
                      algorithm={@algorithm}
                      tokens={stage.value}
                      options={@image}
                      detected={@detected}
                    />
                  <% stage.kind == :symbols -> %>
                    <.symbols_view
                      algorithm={@algorithm}
                      tokens={stage.value}
                      id={"stage-symbols-#{i}"}
                    />
                  <% true -> %>
                    <.output id={"stage-text-#{i}"} text={stage.value} />
                <% end %>
              </div>
            </li>
          </ol>
        </section>
      </div>
    </Layouts.app>
    """
  end

  attr :algorithm, :any, required: true
  attr :symbols, :list, required: true

  # Composes symbol cipher text by clicking the symbols of the key.
  defp symbol_keyboard(assigns) do
    ~H"""
    <div class="space-y-2">
      <p class="text-sm font-medium">Cipher symbols to decode</p>
      <div
        id="composed-symbols"
        class="min-h-14 rounded-lg border border-base-300 bg-base-200/50 p-2"
      >
        <.symbols_view algorithm={@algorithm} tokens={@symbols} id="composed" />
        <p :if={@symbols == []} class="text-sm text-base-content/50 p-1">
          Click the symbols below to write the cipher text.
        </p>
      </div>
      <div id="symbol-keyboard" class="flex flex-wrap gap-1.5">
        <button
          :for={{entry, i} <- Enum.with_index(@algorithm.symbol_key)}
          type="button"
          id={"key-#{i}"}
          phx-click="add_symbol"
          phx-value-index={i}
          class="grid place-items-center rounded-md border border-base-300 bg-base-100 p-1 transition hover:border-primary hover:-translate-y-0.5"
          aria-label={"Symbol #{i + 1}"}
        >
          <.key_glyph algorithm={@algorithm} entry={entry} />
        </button>
      </div>
      <div class="flex flex-wrap gap-2">
        <button
          type="button"
          id="key-space"
          class="btn btn-sm"
          phx-click="add_char"
          phx-value-char="space"
        >
          Space
        </button>
        <button
          type="button"
          id="key-newline"
          class="btn btn-sm"
          phx-click="add_char"
          phx-value-char="newline"
        >
          New line
        </button>
        <button
          type="button"
          id="key-backspace"
          class="btn btn-sm"
          phx-click="backspace"
          aria-label="Delete the last symbol"
        >
          <.icon name="hero-backspace" class="size-4" />
        </button>
        <button type="button" id="key-clear" class="btn btn-sm btn-ghost" phx-click="clear">
          Clear
        </button>
      </div>
    </div>
    """
  end

  attr :algorithm, :any, required: true
  attr :tokens, :list, required: true
  attr :id, :string, required: true

  # Symbol tokens drawn with the key's glyphs, lines and spaces kept.
  defp symbols_view(assigns) do
    lines =
      Enum.chunk_by(assigns.tokens, &(&1 == {:char, "\n"}))
      |> Enum.reject(&(&1 == [{:char, "\n"}]))

    assigns = assign(assigns, :lines, lines)

    ~H"""
    <div id={@id} class="space-y-2">
      <div :for={line <- @lines} class="flex flex-wrap items-end gap-1">
        <%= for token <- line do %>
          <%= case token do %>
            <% {:symbol, i} -> %>
              <.key_glyph algorithm={@algorithm} entry={Enum.at(@algorithm.symbol_key, i)} />
            <% {:char, " "} -> %>
              <span class="w-4" aria-hidden="true"></span>
            <% {:char, char} -> %>
              <span class="font-mono text-lg text-base-content/60">{char}</span>
            <% {:missing, letter} -> %>
              <span
                class="grid place-items-center h-9 min-w-7 rounded border border-dashed border-error/60 font-mono text-error"
                title={"No symbol for #{letter} in the key"}
              >
                {letter}
              </span>
          <% end %>
        <% end %>
      </div>
    </div>
    """
  end

  attr :algorithm, :any, required: true
  attr :entry, :map, required: true

  # A symbol of the key, cropped from its picture with CSS.
  defp key_glyph(assigns) do
    %{algorithm: algorithm, entry: entry} = assigns
    image = Enum.at(algorithm.images, entry["image"])
    scale = @symbol_height / max(image["glyph_height"] || entry["h"], 1)
    pad = 2

    style =
      Enum.join(
        [
          "width: #{px((entry["w"] + 2 * pad) * scale)}",
          "height: #{px((entry["h"] + 2 * pad) * scale)}",
          "background-image: url('#{image["path"]}')",
          "background-size: #{px(image["width"] * scale)} #{px(image["height"] * scale)}",
          "background-position: #{px(-(entry["x"] - pad) * scale)} #{px(-(entry["y"] - pad) * scale)}"
        ],
        "; "
      )

    assigns = assign(assigns, :style, style)

    ~H"""
    <span class="block bg-no-repeat rounded-sm" style={@style} aria-hidden="true"></span>
    """
  end

  attr :algorithm, :any, required: true
  attr :tokens, :list, required: true

  attr :options, :map,
    required: true,
    doc: "style, align, background / ink (\"auto\" or #rrggbb), transparent"

  attr :detected, :map, required: true, doc: "the colours detected by the hook"

  # The encoded symbols as one image, drawn by the SymbolImage hook, with its
  # options (style, alignment, colours) and a PNG download.
  defp symbol_image(assigns) do
    assigns = assign(assigns, :spec, Jason.encode!(image_spec(assigns)))

    ~H"""
    <div
      id="symbol-image"
      phx-hook="SymbolImage"
      data-spec={@spec}
      data-filename={"#{@algorithm.title} - encoded"}
      class="space-y-3"
    >
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
              class={["btn btn-xs join-item", @options.style == style && "btn-primary"]}
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
              class={["btn btn-xs join-item", @options.align == align && "btn-primary"]}
              phx-click="image_align"
              phx-value-align={align}
              aria-pressed={to_string(@options.align == align)}
              aria-label={"Align #{align}"}
              title={"Align #{align}"}
            >
              <.icon name={icon} class="size-4" />
            </button>
          </div>
        </div>
        <button
          type="button"
          id="download-image"
          class="btn btn-xs btn-ghost ml-auto"
          data-download
        >
          <.icon name="hero-arrow-down-tray" class="size-4" /> Download PNG
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
            class={["btn btn-xs", @options.transparent && "btn-primary"]}
            aria-pressed={to_string(@options.transparent)}
            title="No background: a PNG to put on anything"
          >
            <span class="inline-block size-3 rounded-sm ring-1 ring-base-content/30 checkerboard"></span>
            Transparent
          </button>
        </div>
      </form>
      <div
        id="symbol-image-canvas"
        phx-update="ignore"
        data-canvas
        class="grid place-items-center rounded-lg bg-base-200/50 p-2"
      >
      </div>
    </div>
    """
  end

  attr :field, :string, required: true
  attr :label, :string, required: true
  attr :value, :string, required: true, doc: "\"auto\" or a #rrggbb colour"
  attr :detected, :any, required: true
  attr :title, :string, required: true
  attr :disabled, :boolean, default: false

  # A colour of the image: the detected one, or one chosen with the picker.
  defp colour_choice(assigns) do
    ~H"""
    <div class={["flex items-center gap-2 transition-opacity", @disabled && "opacity-40"]}>
      <span class="text-base-content/70">{@label}</span>
      <button
        type="button"
        id={"#{@field}-auto"}
        phx-click="image_auto"
        phx-value-colour={@field}
        disabled={@disabled}
        class={["btn btn-xs", @value == "auto" && "btn-primary"]}
        aria-pressed={to_string(@value == "auto")}
        title={@title}
      >
        <span
          class="inline-block size-3 rounded-sm ring-1 ring-base-content/30"
          style={"background: #{@detected || "transparent"}"}
        ></span>
        Detected
      </button>
      <input
        type="color"
        id={"#{@field}-color"}
        name={@field}
        value={if @value == "auto", do: @detected || "#ffffff", else: @value}
        disabled={@disabled}
        class="size-7 cursor-pointer rounded border border-base-300 bg-transparent disabled:cursor-not-allowed"
        aria-label={"#{@label} colour"}
        title={"Choose the #{String.downcase(@label)} colour"}
      />
      <span :if={@value != "auto"} class="font-mono text-xs">{@value}</span>
    </div>
    """
  end

  # What the SymbolImage hook draws: the pictures, and lines of tokens
  # (glyph crops scaled to a common height, spaces, characters), with the
  # image options.
  defp image_spec(%{algorithm: algorithm, tokens: tokens, options: options}) do
    lines =
      tokens
      |> Enum.chunk_by(&(&1 == {:char, "\n"}))
      |> Enum.reject(&(&1 == [{:char, "\n"}]))
      |> Enum.map(fn line -> Enum.map(line, &image_token(algorithm, &1)) end)

    Map.merge(options, %{
      images: Enum.map(algorithm.images, & &1["path"]),
      lines: lines,
      line_height: @symbol_height + 16
    })
  end

  defp image_token(algorithm, {:symbol, i}) do
    entry = Enum.at(algorithm.symbol_key, i)
    image = Enum.at(algorithm.images, entry["image"])
    scale = @symbol_height / max(image["glyph_height"] || entry["h"], 1)

    %{
      t: "glyph",
      i: entry["image"],
      x: entry["x"],
      y: entry["y"],
      w: entry["w"],
      h: entry["h"],
      scale: scale
    }
  end

  defp image_token(_algorithm, {:char, " "}), do: %{t: "space"}
  defp image_token(_algorithm, {:char, char}), do: %{t: "char", c: char}
  defp image_token(_algorithm, {:missing, letter}), do: %{t: "missing", c: letter}

  defp px(v), do: "#{Float.round(v * 1.0, 2)}px"
end
