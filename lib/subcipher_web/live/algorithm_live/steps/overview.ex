defmodule SubcipherWeb.AlgorithmLive.Steps.Overview do
  @moduledoc "The steps of an algorithm, read-only, with their settings."
  use SubcipherWeb, :html

  attr :steps, :list, required: true, doc: "see SubcipherWeb.AlgorithmLive.Steps.Summaries"
  attr :owner, :boolean, required: true, doc: "can edit the steps"

  def steps_overview(assigns) do
    ~H"""
    <section
      id="algorithm-steps"
      class="rounded-2xl border border-base-300 bg-base-100 p-4 sm:p-6 space-y-3"
    >
      <h2 class="flex items-center justify-between gap-2 text-xs font-semibold uppercase tracking-wider text-base-content/50">
        Steps
        <button
          :if={@owner}
          type="button"
          id="edit-algorithm"
          class="btn btn-ghost btn-sm normal-case tracking-normal"
          phx-click="toggle_edit"
        >
          <.icon name="hero-pencil-square" class="size-5" /> Edit
        </button>
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
    """
  end
end
