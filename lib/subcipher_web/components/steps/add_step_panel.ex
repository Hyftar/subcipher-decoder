defmodule SubcipherWeb.Components.AddStepPanel do
  @moduledoc "The \"add a step\" view of a puzzle: every cipher to choose from."
  use SubcipherWeb, :html

  import SubcipherWeb.Components.CipherGrid

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
end
