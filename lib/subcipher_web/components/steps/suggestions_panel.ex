defmodule SubcipherWeb.Components.SuggestionsPanel do
  @moduledoc "Suggested settings of a step and its solver, in a collapsed accordion."
  use SubcipherWeb, :html

  import SubcipherWeb.Components.{Accordion, SolverCard, SuggestionCard}

  attr :id, :string, required: true, doc: "suffix of the element ids (a step id, \"symbols\"…)"

  attr :suggestions, :list,
    default: [],
    doc: "%{label, reason, preview, applied, use: %JS{}} each"

  attr :solver, :map,
    default: nil,
    doc:
      "%{state: :idle | :running | {:ok, suggestion} | {:error, message}, start: %JS{}}; nil without solver"

  attr :class, :any,
    default: "rounded-2xl border border-base-300 bg-base-100",
    doc: "classes of the frame (see `SubcipherWeb.Components.Accordion`)"

  @doc """
  Suggested settings, each with the reason it was suggested and a preview
  of the result; "Use" applies one. They often give the answer away, so the
  panel (an accordion) stays collapsed until opened. With a `solver`, a "Try
  to solve" card inside it runs it (in the background, on demand) and shows
  its result like a suggestion.
  """
  def suggestions_panel(assigns) do
    ~H"""
    <.accordion
      id={"suggestions-#{@id}"}
      icon="hero-sparkles"
      class={@class}
    >
      <:title>Suggestions</:title>
      <:hint>Hidden so they don't spoil the puzzle</:hint>
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
        <.solver_card :if={@solver} id={@id} solver={@solver} />
      </ol>
    </.accordion>
    """
  end
end
