defmodule SubcipherWeb.Components.SuggestionsPanel do
  @moduledoc "Suggested settings of a step (hidden until asked for) and its solver."
  use SubcipherWeb, :html

  import SubcipherWeb.Components.{SolverCard, SuggestionCard}

  attr :id, :string, required: true, doc: "suffix of the element ids (a step id, \"symbols\"…)"

  attr :suggestions, :list,
    default: [],
    doc: "%{label, reason, preview, applied, use: %JS{}} each"

  attr :solver, :map,
    default: nil,
    doc:
      "%{state: :idle | :running | {:ok, suggestion} | {:error, message}, start: %JS{}}; nil without solver"

  attr :shown, :boolean,
    default: false,
    doc: "the suggestions are hidden until asked for (\"toggle_suggestions\" with `panel: id`)"

  @doc """
  Suggested settings, each with the reason it was suggested and a preview
  of the result; "Use" applies one. They often give the answer away, so they
  stay hidden until asked for. With a `solver`, a "Try to solve" card runs it
  (in the background, on demand) and shows its result like a suggestion.
  """
  def suggestions_panel(assigns) do
    ~H"""
    <div id={"suggestions-#{@id}"} class="space-y-3 min-w-0">
      <div class="flex flex-wrap items-center justify-between gap-2">
        <h3 class="flex items-center gap-1.5 text-xs font-semibold uppercase tracking-wider text-base-content/50">
          <.icon name="hero-sparkles" class="size-5" /> Suggestions
        </h3>
        <button
          type="button"
          id={"toggle-suggestions-#{@id}"}
          class={["btn btn-sm", if(@shown, do: "btn-ghost", else: "btn-soft btn-primary")]}
          phx-click={JS.push("toggle_suggestions", value: %{panel: @id})}
          aria-expanded={to_string(@shown)}
        >
          <.icon name={if @shown, do: "hero-eye-slash", else: "hero-eye"} class="size-5" />
          {if @shown, do: "Hide suggestions", else: "Show suggestions"}
        </button>
      </div>
      <p :if={!@shown} class="text-sm text-base-content/60">
        Hidden so they don't spoil the puzzle.
      </p>
      <p :if={@shown and @suggestions == [] and !@solver} class="text-sm text-base-content/60">
        No suggestions for this input (it may be too short to analyse).
      </p>
      <ol class="grid grid-cols-[minmax(0,1fr)] gap-2">
        <.suggestion_card
          :for={{suggestion, i} <- if(@shown, do: Enum.with_index(@suggestions), else: [])}
          id={"suggestion-#{@id}-#{i}"}
          use_id={"apply-suggestion-#{@id}-#{i}"}
          suggestion={suggestion}
        />
        <.solver_card :if={@solver} id={@id} solver={@solver} />
      </ol>
    </div>
    """
  end
end
