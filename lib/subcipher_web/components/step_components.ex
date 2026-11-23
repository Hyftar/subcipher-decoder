defmodule SubcipherWeb.StepComponents do
  @moduledoc """
  Rendering of the decoding steps (see `Subcipher.Steps`) on the puzzle page:
  the step navigation, a step's card and the "add a step" chooser.

  Parameter forms are generated from each cipher's `fields/0`, so a new
  cipher type gets its form without touching this module, as long as it
  uses the existing field types (`:integer`, `:string`, `:select`,
  `:letter_map`, `:symbol_map`).
  """
  use SubcipherWeb, :html

  alias Subcipher.Steps
  alias Subcipher.Steps.Alphabet
  alias Subcipher.Steps.Ciphers.{Anagram, SymbolSubstitution}

  ## Navigation

  attr :puzzle, :any, required: true
  attr :nodes, :list, required: true, doc: "[%{number:, label:, icon:}] in order"
  attr :selected, :any, required: true, doc: "number of the shown step, or :new"

  @doc "Steps as connected circles; the last one adds a step."
  def step_nav(assigns) do
    ~H"""
    <nav id="step-nav" aria-label="Decoding steps" class="overflow-x-auto">
      <ol class="flex items-start min-w-max px-1 pt-1 pb-2">
        <%= for node <- @nodes do %>
          <li class="flex flex-col items-center gap-1.5 w-24">
            <.link
              patch={~p"/puzzles/#{@puzzle}?step=#{node.number}"}
              id={"step-nav-#{node.number}"}
              aria-current={if node.number == @selected, do: "step"}
              title={node.label}
              class={[
                "relative grid place-items-center size-10 rounded-full border-2 font-semibold transition-all",
                if(node.number == @selected,
                  do:
                    "bg-primary border-primary text-primary-content ring-4 ring-primary/20 scale-105",
                  else: "bg-base-100 border-base-300 hover:border-primary hover:text-primary"
                )
              ]}
            >
              {node.number}
              <span
                :if={node[:icon]}
                class="absolute -bottom-1 -right-1 grid place-items-center size-4 rounded-full bg-base-100 text-base-content/60 ring-1 ring-base-300"
              >
                <.icon name={node.icon} class="size-3" />
              </span>
            </.link>
            <span class={[
              "text-xs text-center leading-tight px-1 line-clamp-2",
              if(node.number == @selected,
                do: "font-semibold text-base-content",
                else: "text-base-content/60"
              )
            ]}>
              {node.label}
            </span>
          </li>
          <li aria-hidden="true" class="flex-1 min-w-6 h-0.5 mt-5 -mx-7 bg-base-300 rounded-full">
          </li>
        <% end %>
        <li class="flex flex-col items-center gap-1.5 w-24">
          <.link
            patch={~p"/puzzles/#{@puzzle}?step=new"}
            id="step-nav-new"
            aria-current={if @selected == :new, do: "step"}
            title="Add a step"
            class={[
              "grid place-items-center size-10 rounded-full border-2 border-dashed transition-all",
              if(@selected == :new,
                do: "border-primary bg-primary/10 text-primary ring-4 ring-primary/20",
                else: "border-base-300 text-base-content/50 hover:border-primary hover:text-primary"
              )
            ]}
          >
            <.icon name="hero-plus" class="size-5" />
          </.link>
          <span class="text-xs text-center text-base-content/60">Add step</span>
        </li>
      </ol>
    </nav>
    """
  end

  ## Adding a step

  attr :first, :boolean, default: false, doc: "no step yet"

  def add_step_panel(assigns) do
    ~H"""
    <section id="add-step" class="rounded-2xl border border-base-300 bg-base-100 p-4 sm:p-6 space-y-4">
      <div>
        <h2 class="font-semibold">Add a step</h2>
        <p class="text-sm text-base-content/60">
          The new step decodes the output of the last step.
        </p>
      </div>
      <.cipher_grid id_prefix="add-step-" event="add_step" icon="hero-plus-circle" />
    </section>
    """
  end

  attr :id_prefix, :string, required: true, doc: "card ids: id_prefix <> cipher type"
  attr :event, :string, required: true, doc: "clicked with phx-value-type"
  attr :icon, :string, default: "hero-arrow-right-circle"
  attr :class, :string, default: "sm:grid-cols-2"

  @doc "Every cipher type as a card; clicking one sends `event` with its type."
  def cipher_grid(assigns) do
    ~H"""
    <div class={["grid gap-3", @class]}>
      <button
        :for={cipher <- Steps.ciphers()}
        type="button"
        id={@id_prefix <> cipher.type()}
        phx-click={@event}
        phx-value-type={cipher.type()}
        class="group flex flex-col justify-start text-left rounded-xl border border-base-300 bg-base-100 p-4 transition hover:border-primary hover:bg-primary/5 hover:-translate-y-0.5 hover:shadow-sm cursor-pointer"
      >
        <span class="flex items-center justify-between gap-2 font-semibold">
          <span class="flex items-center gap-2">
            {cipher.name()}
            <.icon
              :if={:pictures in cipher.input_kinds()}
              name="hero-photo"
              class="size-4 text-base-content/40"
            />
          </span>
          <.icon
            name={@icon}
            class="size-5 shrink-0 text-base-content/30 group-hover:text-primary transition-colors"
          />
        </span>
        <span class="block mt-1 text-sm text-base-content/60">{cipher.description()}</span>
        <.osrs_usage cipher={cipher} class="mt-2" />
      </button>
    </div>
    """
  end

  ## A step

  attr :number, :integer, required: true, doc: "displayed step number"
  attr :result, :map, required: true, doc: "an entry of Subcipher.Steps.run/2"
  attr :form, :any, required: true

  attr :solver_state, :any,
    default: nil,
    doc: "nil (no solver), :idle, :running, {:ok, suggestion} or {:error, message}"

  attr :suggestions, :any,
    default: nil,
    doc: "Subcipher.Steps.suggestions/3: a list, or nil when the cipher doesn't suggest"

  attr :can_move_up, :boolean, required: true
  attr :can_move_down, :boolean, required: true
  attr :can_delete, :boolean, required: true
  attr :input_form, :any, default: nil, doc: "editable puzzle input (first step of a text puzzle)"

  def step_card(assigns) do
    assigns =
      assign(assigns,
        step: assigns.result.step,
        cipher: assigns.result.cipher,
        summary: summary(assigns.result.cipher, assigns.result.params),
        type_form: to_form(%{"type" => assigns.result.step.type}, as: :step_type)
      )

    ~H"""
    <section
      id={"step-#{@step.id}"}
      class="rounded-2xl border border-base-300 bg-base-100 p-4 sm:p-6 space-y-5"
    >
      <div class="flex flex-wrap items-center gap-3">
        <span class="grid place-items-center size-8 rounded-full bg-primary text-primary-content text-sm font-semibold">
          {@number}
        </span>
        <.form
          for={@type_form}
          id={"step-type-form-#{@step.id}"}
          phx-change="change_step_type"
          class="flex-1 min-w-48"
        >
          <input type="hidden" name="step_id" value={@step.id} />
          <label class="sr-only" for={"step-type-#{@step.id}"}>Cipher</label>
          <select
            id={"step-type-#{@step.id}"}
            name="type"
            class="select select-sm font-semibold w-auto"
            title="Changing the cipher resets the settings of this step"
          >
            <option
              :for={cipher <- Steps.ciphers()}
              value={cipher.type()}
              selected={cipher.type() == @step.type}
            >
              {cipher.name()}
            </option>
          </select>
        </.form>
        <div class="flex items-center">
          <button
            type="button"
            id={"move-step-up-#{@step.id}"}
            class="btn btn-ghost btn-sm btn-square"
            phx-click="move_step"
            phx-value-id={@step.id}
            phx-value-direction="up"
            disabled={!@can_move_up}
            aria-label="Move step earlier"
            title="Move earlier"
          >
            <.icon name="hero-arrow-left" class="size-4" />
          </button>
          <button
            type="button"
            id={"move-step-down-#{@step.id}"}
            class="btn btn-ghost btn-sm btn-square"
            phx-click="move_step"
            phx-value-id={@step.id}
            phx-value-direction="down"
            disabled={!@can_move_down}
            aria-label="Move step later"
            title="Move later"
          >
            <.icon name="hero-arrow-right" class="size-4" />
          </button>
          <button
            type="button"
            id={"delete-step-#{@step.id}"}
            class="btn btn-ghost btn-sm btn-square"
            phx-click="delete_step"
            phx-value-id={@step.id}
            disabled={!@can_delete}
            data-confirm={"Remove step #{@number} (#{@cipher.name()})?"}
            aria-label="Remove step"
            title={if @can_delete, do: "Remove step", else: "A text cipher needs at least one step"}
          >
            <.icon name="hero-trash" class="size-4" />
          </button>
        </div>
      </div>
      <div class="-mt-3 space-y-1">
        <p class="text-sm text-base-content/60">{@cipher.description()}</p>
        <.osrs_usage cipher={@cipher} />
      </div>

      <div class="space-y-1.5">
        <h3 class="text-xs font-semibold uppercase tracking-wider text-base-content/50">
          {if @input_form, do: "Cipher text", else: "Input · output of step #{@number - 1}"}
        </h3>
        <.form
          :if={@input_form}
          for={@input_form}
          id="input-form"
          phx-change="update_input"
          phx-submit="update_input"
        >
          <textarea
            id="input-text"
            name={@input_form[:input_text].name}
            rows="5"
            phx-debounce="400"
            spellcheck="false"
            placeholder="Paste the cipher text here"
            class="w-full rounded-lg border border-base-300 bg-base-200/50 p-3 font-mono text-lg leading-relaxed tracking-wider focus:outline-none focus:ring-2 focus:ring-primary/40"
          >{Phoenix.HTML.Form.normalize_value("textarea", @input_form[:input_text].value)}</textarea>
        </.form>
        <pre
          :if={!@input_form}
          id={"step-input-#{@step.id}"}
          class="max-h-48 overflow-y-auto rounded-lg border border-dashed border-base-300 p-3 font-mono text-base text-base-content/70 whitespace-pre-wrap break-words tracking-wider"
        >{@result.input}</pre>
      </div>

      <div :if={@cipher.fields() != []} class="space-y-2">
        <h3 class="text-xs font-semibold uppercase tracking-wider text-base-content/50">
          Settings
        </h3>
        <.form
          for={@form}
          id={"step-form-#{@step.id}"}
          phx-change="update_step"
          phx-submit="update_step"
          class="space-y-2"
        >
          <input type="hidden" name="step_id" value={@step.id} />
          <.param_field
            :for={field <- @cipher.fields()}
            field={field}
            form_field={@form[field.name]}
            step_id={@step.id}
            input={@result.input}
            params={@result.params}
          />
        </.form>
        <pre
          :if={@summary}
          id={"step-summary-#{@step.id}"}
          class="text-xs font-mono text-base-content/60 whitespace-pre-wrap"
        >{@summary}</pre>
      </div>

      <.suggestions_panel
        :if={@suggestions || @solver_state}
        id={to_string(@step.id)}
        suggestions={Enum.map(@suggestions || [], &Map.put(&1, :use, use_params(@step, &1)))}
        solver={
          @solver_state &&
            %{
              state: with_use(@solver_state, @step),
              start: JS.push("solve", value: %{target: @step.id})
            }
        }
      />

      <div class="space-y-1.5">
        <h3 class="text-xs font-semibold uppercase tracking-wider text-base-content/50">Output</h3>
        <.output id={"step-output-#{@step.id}"} text={@result.output} />
      </div>
    </section>
    """
  end

  defp use_params(step, suggestion),
    do: JS.push("apply_suggestion", value: %{id: step.id, params: suggestion.params})

  defp with_use({:ok, solution}, step),
    do: {:ok, Map.put(solution, :use, use_params(step, solution))}

  defp with_use(state, _step), do: state

  attr :id, :string, required: true, doc: "suffix of the element ids (a step id, \"symbols\"…)"

  attr :suggestions, :list,
    default: [],
    doc: "%{label, reason, preview, applied, use: %JS{}} each"

  attr :solver, :map,
    default: nil,
    doc:
      "%{state: :idle | :running | {:ok, suggestion} | {:error, message}, start: %JS{}}; nil without solver"

  @doc """
  Suggested settings, each with the reason it was suggested and a preview
  of the result; "Use" applies one. With a `solver`, a "Try to solve" card
  runs it (in the background) and shows its result like a suggestion.
  """
  def suggestions_panel(assigns) do
    ~H"""
    <div id={"suggestions-#{@id}"} class="space-y-2 min-w-0">
      <h3 class="flex items-center gap-1.5 text-xs font-semibold uppercase tracking-wider text-base-content/50">
        <.icon name="hero-sparkles" class="size-4" /> Suggestions
      </h3>
      <p :if={@suggestions == [] and !@solver} class="text-sm text-base-content/60">
        No suggestions for this input (it may be too short to analyse).
      </p>
      <ol class="grid grid-cols-[minmax(0,1fr)] gap-2">
        <.suggestion_card
          :for={{suggestion, i} <- Enum.with_index(@suggestions)}
          id={"suggestion-#{@id}-#{i}"}
          use_id={"apply-suggestion-#{@id}-#{i}"}
          suggestion={suggestion}
        />
        <li
          :if={@solver}
          id={"solver-#{@id}"}
          class="min-w-0 rounded-xl border border-dashed border-primary/40 bg-primary/5 p-3 space-y-2"
        >
          <div class="flex flex-wrap items-center gap-2">
            <span class="font-semibold text-sm flex items-center gap-1.5">
              <.icon name="hero-cpu-chip" class="size-4" /> Try to solve
            </span>
            <span
              :if={@solver.state == :running}
              class="flex items-center gap-1.5 text-sm text-base-content/70"
            >
              <span class="loading loading-spinner loading-xs"></span> Solving…
            </span>
            <button
              :if={@solver.state != :running}
              type="button"
              id={"solve-#{@id}"}
              class="btn btn-primary btn-xs ml-auto"
              phx-click={@solver.start}
            >
              {if @solver.state == :idle, do: "Solve", else: "Solve again"}
            </button>
          </div>
          <p :if={@solver.state in [:idle, :running]} class="text-sm text-base-content/70">
            Searches for the letters that make the text read most like English (a second or
            two). Letters you already set are kept, so fixing a few and solving again helps.
          </p>
          <p :if={match?({:error, _}, @solver.state)} class="text-sm text-error">
            {elem(@solver.state, 1)}
          </p>
          <ol :if={match?({:ok, _}, @solver.state)}>
            <.suggestion_card
              id={"solution-#{@id}"}
              use_id={"apply-solution-#{@id}"}
              suggestion={elem(@solver.state, 1)}
            />
          </ol>
        </li>
      </ol>
    </div>
    """
  end

  attr :id, :string, required: true
  attr :use_id, :string, required: true
  attr :suggestion, :map, required: true

  defp suggestion_card(assigns) do
    ~H"""
    <li
      id={@id}
      class={[
        "min-w-0 rounded-xl border p-3 transition-colors bg-base-100",
        if(@suggestion.applied,
          do: "border-success/50 bg-success/5",
          else: "border-base-300 hover:border-primary/50"
        )
      ]}
    >
      <div class="flex flex-wrap items-center gap-2">
        <span class="font-semibold text-sm">{@suggestion.label}</span>
        <span :if={@suggestion.applied} class="badge badge-sm badge-success badge-soft">
          <.icon name="hero-check" class="size-3" /> Applied
        </span>
        <button
          :if={!@suggestion.applied}
          type="button"
          id={@use_id}
          class="btn btn-primary btn-soft btn-xs ml-auto"
          phx-click={@suggestion.use}
        >
          Use
        </button>
      </div>
      <p class="mt-1 text-sm text-base-content/70">{@suggestion.reason}</p>
      <p class="mt-1.5 font-mono text-sm truncate text-base-content/90" title={@suggestion.preview}>
        {@suggestion.preview}
      </p>
    </li>
    """
  end

  attr :field, :map, required: true, doc: "a cipher field spec"
  attr :form_field, Phoenix.HTML.FormField, required: true
  attr :step_id, :integer, required: true
  attr :input, :string, required: true, doc: "the step's input text"
  attr :params, :map, default: %{}, doc: "the step's current (valid) parameters"

  # A slider; its maximum can depend on the step's input.
  defp param_field(%{field: %{type: :integer, control: :range}} = assigns) do
    %{field: field, input: input} = assigns
    max = if is_function(field[:max], 1), do: field.max.(input), else: field[:max]

    value =
      case assigns.form_field.value do
        nil -> if is_function(field[:auto], 1), do: field.auto.(input), else: field[:min]
        "" -> field[:min]
        value -> value
      end

    assigns = assign(assigns, max: max, value: min(to_integer(value), max))

    ~H"""
    <div class="max-w-sm space-y-1">
      <label for={@form_field.id} class="flex items-center justify-between text-sm font-medium">
        {@field.label}
        <span id={"#{@form_field.id}-value"} class="badge badge-sm badge-primary tabular-nums">
          {@value}
        </span>
      </label>
      <input
        type="range"
        id={@form_field.id}
        name={@form_field.name}
        min={@field[:min]}
        max={@max}
        value={@value}
        step="1"
        disabled={@max == @field[:min]}
        phx-debounce="100"
        class="range range-primary range-sm w-full"
      />
      <div class="flex justify-between text-[10px] text-base-content/50 tabular-nums">
        <span>{@field[:min]}</span><span>{@max}</span>
      </div>
      <p :if={@field[:help]} class="text-xs text-base-content/60">{@field.help}</p>
      <.field_errors form_field={@form_field} />
    </div>
    """
  end

  defp param_field(%{field: %{type: :integer}} = assigns) do
    ~H"""
    <div class="max-w-xs">
      <.input
        field={@form_field}
        type="number"
        label={@field.label}
        min={@field[:min]}
        max={@field[:max]}
        phx-debounce="200"
      />
      <p :if={@field[:help]} class="-mt-1 text-xs text-base-content/60">{@field.help}</p>
    </div>
    """
  end

  defp param_field(%{field: %{type: :string}} = assigns) do
    ~H"""
    <div class="max-w-sm">
      <.input field={@form_field} type="text" label={@field.label} phx-debounce="300" />
      <p :if={@field[:help]} class="-mt-1 text-xs text-base-content/60">{@field.help}</p>
    </div>
    """
  end

  defp param_field(%{field: %{type: :select}} = assigns) do
    ~H"""
    <div class="max-w-sm">
      <.input field={@form_field} type="select" label={@field.label} options={@field.options} />
      <p :if={@field[:help]} class="-mt-1 text-xs text-base-content/60">{@field.help}</p>
    </div>
    """
  end

  # The input's characters as tiles, in the current order. Reordered by drag
  # and drop, by tapping two tiles, or with ←/→ on a focused tile (see the
  # AnagramTiles hook, which sends the new order as "update_step").
  defp param_field(%{field: %{type: :permutation}} = assigns) do
    tiles = Anagram.tiles(assigns.input, assigns.params[:spaces])
    order = Anagram.resolve_order(assigns.form_field.value, length(tiles))
    tiles = List.to_tuple(tiles)
    assigns = assign(assigns, tiles: Enum.map(order, &{&1, elem(tiles, &1)}))

    ~H"""
    <fieldset class="space-y-2">
      <legend class="text-sm font-medium">{@field.label}</legend>
      <input type="hidden" name={@form_field.name} value={@form_field.value} />
      <p :if={@tiles == []} class="text-sm text-base-content/60">Nothing to rearrange yet.</p>
      <ol
        :if={@tiles != []}
        id={"anagram-#{@step_id}"}
        phx-hook="AnagramTiles"
        data-step-id={@step_id}
        aria-label="Characters, in reading order"
        class="relative flex flex-wrap gap-1.5 select-none"
      >
        <li
          :for={{index, char} <- @tiles}
          id={"tile-#{@step_id}-#{index}"}
          data-index={index}
          draggable="true"
          tabindex="0"
          role="button"
          aria-label={if char =~ ~r/^\s$/u, do: "space", else: char}
          class={[
            "grid place-items-center min-w-10 h-11 px-2 rounded-lg border-2 border-b-4 font-mono text-xl uppercase",
            "cursor-grab active:cursor-grabbing transition-all duration-150",
            "focus:outline-none focus-visible:ring-2 focus-visible:ring-primary",
            if(char =~ ~r/^\s$/u,
              do: "border-dashed border-base-300 text-base-content/30",
              else: "border-base-300 bg-base-100 hover:border-primary/60 hover:-translate-y-0.5"
            )
          ]}
        >
          {if char =~ ~r/^\s$/u, do: "␣", else: char}
        </li>
      </ol>
      <div class="flex flex-wrap items-center gap-3 text-xs text-base-content/60">
        <span>Drag a tile, or tap two tiles; ← / → move a focused tile.</span>
        <button
          type="button"
          id={"anagram-reset-#{@step_id}"}
          class="btn btn-ghost btn-xs"
          phx-click={JS.push("update_step", value: %{step_id: @step_id, step: %{order: ""}})}
        >
          <.icon name="hero-arrow-uturn-left" class="size-3.5" /> Reset
        </button>
      </div>
      <.field_errors form_field={@form_field} />
    </fieldset>
    """
  end

  # One small input per cipher letter, with how often it appears in the
  # step's input as a hint.
  defp param_field(%{field: %{type: :letter_map}} = assigns) do
    assigns =
      assign(assigns,
        mapping: assigns.form_field.value || %{},
        frequencies: Alphabet.frequencies(assigns.input)
      )

    ~H"""
    <fieldset>
      <legend class="text-sm font-medium mb-1">{@field.label}</legend>
      <div class="grid grid-cols-7 sm:grid-cols-13 gap-1.5">
        <label
          :for={letter <- Alphabet.letters()}
          for={"step-#{@step_id}-map-#{letter}"}
          class={[
            "flex flex-col items-center rounded-md border px-1 pt-1 pb-1.5 transition-colors",
            if(Map.get(@frequencies, letter),
              do: "border-base-300 bg-base-100",
              else: "border-transparent bg-base-200/40 opacity-60"
            )
          ]}
        >
          <span class="font-mono text-sm font-semibold">{letter}</span>
          <span class="text-[10px] leading-3 text-base-content/50">
            ×{Map.get(@frequencies, letter, 0)}
          </span>
          <input
            type="text"
            id={"step-#{@step_id}-map-#{letter}"}
            name={"#{@form_field.name}[#{letter}]"}
            value={Map.get(@mapping, letter)}
            maxlength="1"
            autocomplete="off"
            spellcheck="false"
            phx-debounce="150"
            aria-label={"Plain letter for #{letter}"}
            class="mt-1 w-7 h-7 rounded border border-base-300 bg-base-100 text-center font-mono uppercase text-primary focus:outline-none focus:ring-2 focus:ring-primary/40"
          />
        </label>
      </div>
      <.field_errors form_field={@form_field} />
    </fieldset>
    """
  end

  # One input per distinct character of the step's input, most frequent
  # first.
  defp param_field(%{field: %{type: :symbol_map}} = assigns) do
    assigns =
      assign(assigns,
        mapping: assigns.form_field.value || %{},
        symbols: Alphabet.symbol_frequencies(assigns.input)
      )

    ~H"""
    <fieldset>
      <legend class="text-sm font-medium mb-1">{@field.label}</legend>
      <p :if={@symbols == []} class="text-sm text-base-content/60">
        No symbols in the input yet.
      </p>
      <div class="grid grid-cols-[repeat(auto-fill,minmax(4rem,1fr))] gap-1.5">
        <label
          :for={{{symbol, count}, i} <- Enum.with_index(@symbols)}
          for={"step-#{@step_id}-symbol-#{i}"}
          class="flex flex-col items-center rounded-md border border-base-300 bg-base-100 px-1 pt-1 pb-1.5"
        >
          <span class="font-mono text-xl leading-7">{symbol}</span>
          <span class="text-[10px] leading-3 text-base-content/50">×{count}</span>
          <input
            type="text"
            id={"step-#{@step_id}-symbol-#{i}"}
            name={"#{@form_field.name}[#{SymbolSubstitution.form_key(symbol)}]"}
            value={Map.get(@mapping, symbol)}
            maxlength="3"
            autocomplete="off"
            spellcheck="false"
            phx-debounce="150"
            aria-label={"Letter for #{symbol}"}
            class="mt-1 w-11 h-7 rounded border border-base-300 bg-base-100 text-center font-mono uppercase text-primary focus:outline-none focus:ring-2 focus:ring-primary/40"
          />
        </label>
      </div>
      <.field_errors form_field={@form_field} />
    </fieldset>
    """
  end

  attr :cipher, :atom, required: true
  attr :class, :string, default: nil

  @doc "Where the cipher is used in Old School RuneScape, if known."
  def osrs_usage(assigns) do
    assigns =
      assign(assigns,
        usage:
          if(Steps.implements?(assigns.cipher, :osrs_usage, 0), do: assigns.cipher.osrs_usage())
      )

    ~H"""
    <p :if={@usage} class={["flex items-center gap-1.5 text-xs text-base-content/60", @class]}>
      <span class="shrink-0 rounded bg-warning/15 px-1 py-px text-[10px] font-bold tracking-wide text-warning">
        OSRS
      </span>
      <span>{@usage}</span>
    </p>
    """
  end

  attr :form_field, Phoenix.HTML.FormField, required: true

  defp field_errors(assigns) do
    ~H"""
    <p :for={msg <- Enum.map(@form_field.errors, &translate_error/1)} class="mt-1 text-sm text-error">
      {msg}
    </p>
    """
  end

  attr :id, :string, required: true
  attr :text, :string, required: true
  attr :class, :string, default: nil

  def output(assigns) do
    ~H"""
    <div class={["relative group rounded-lg bg-base-200/50", @class]}>
      <button
        type="button"
        class="absolute top-1.5 right-1.5 btn btn-ghost btn-xs opacity-60 group-hover:opacity-100"
        phx-click={JS.dispatch("phx:copy", to: "##{@id}")}
        aria-label="Copy"
        title="Copy"
      >
        <.icon name="hero-clipboard" class="size-4" />
      </button>
      <pre
        id={@id}
        class="p-3 pr-10 font-mono text-lg whitespace-pre-wrap break-words leading-relaxed tracking-wider"
      >{@text}</pre>
    </div>
    """
  end

  defp to_integer(value) when is_integer(value), do: value

  defp to_integer(value) do
    case Integer.parse(to_string(value)) do
      {i, _} -> i
      :error -> 0
    end
  end

  defp summary(cipher, params) do
    if Steps.implements?(cipher, :summary, 1), do: cipher.summary(params)
  end
end
