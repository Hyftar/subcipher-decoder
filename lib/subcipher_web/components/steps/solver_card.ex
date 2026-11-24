defmodule SubcipherWeb.Components.SolverCard do
  @moduledoc """
  "Try to solve": runs the step's solver (in the background, on demand) and
  shows its result like a suggestion.
  """
  use SubcipherWeb, :html

  import SubcipherWeb.Components.SuggestionCard

  attr :id, :string, required: true, doc: "suffix of the element ids (a step id, \"symbols\"…)"

  attr :solver, :map,
    required: true,
    doc:
      "%{state: :idle | :running | {:ok, suggestion} | {:error, message}, start: %JS{}, help: text or nil}"

  def solver_card(assigns) do
    ~H"""
    <li
      id={"solver-#{@id}"}
      class="min-w-0 rounded-xl border border-dashed border-primary/40 bg-primary/5 p-3 space-y-2"
    >
      <div class="flex flex-wrap items-center gap-2">
        <span class="font-semibold text-sm flex items-center gap-1.5">
          <.icon name="hero-cpu-chip" class="size-5" /> Try to solve
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
          class="btn btn-primary btn-sm ml-auto"
          phx-click={@solver.start}
        >
          {if @solver.state == :idle, do: "Solve", else: "Solve again"}
        </button>
      </div>
      <p :if={@solver.state in [:idle, :running]} class="text-sm text-base-content/70">
        {@solver[:help] ||
          "Searches for the letters that make the text read most like English (a second or two). " <>
            "Letters you already set are kept, so fixing a few and solving again helps."}
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
    """
  end
end
