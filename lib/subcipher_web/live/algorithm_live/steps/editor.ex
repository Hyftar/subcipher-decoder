defmodule SubcipherWeb.AlgorithmLive.Steps.Editor do
  @moduledoc """
  The steps of an algorithm, editable: cipher, settings, order; and adding
  a step. Only ciphers that can encode are offered. A pictures algorithm's
  symbol key (step 1) comes from its puzzle and isn't edited here.
  """
  use SubcipherWeb, :html

  alias Subcipher.Algorithms
  alias Subcipher.Algorithms.Algorithm

  import SubcipherWeb.Components.CipherGrid
  import SubcipherWeb.AlgorithmLive.Steps.EditorStep

  attr :algorithm, :any, required: true
  attr :steps, :list, required: true, doc: "see SubcipherWeb.AlgorithmLive.Steps.EditorSteps"

  def steps_editor(assigns) do
    assigns = assign(assigns, ciphers: Algorithms.ciphers())

    ~H"""
    <section id="steps-editor" class="space-y-4">
      <div class="flex items-center justify-between gap-2">
        <h2 class="text-xs font-semibold uppercase tracking-wider text-base-content/50">
          Steps · decoding order
        </h2>
        <button
          type="button"
          id="done-editing"
          class="btn btn-primary"
          phx-click="toggle_edit"
        >
          <.icon name="hero-check" class="size-5" /> Done
        </button>
      </div>

      <div
        :if={Algorithm.pictures?(@algorithm)}
        id="editor-step-symbols"
        class="flex items-center gap-3 rounded-2xl border border-dashed border-base-300 bg-base-100 p-4"
      >
        <span class="grid place-items-center size-8 rounded-full bg-base-200 text-sm font-semibold">
          1
        </span>
        <div>
          <p class="font-semibold">Symbol substitution</p>
          <p class="text-sm text-base-content/60">
            {length(@algorithm.symbol_key)} symbols in the key, from the puzzle's pictures.
          </p>
        </div>
      </div>

      <.editor_step
        :for={step <- @steps}
        step={step}
        count={length(@steps)}
        algorithm={@algorithm}
        ciphers={@ciphers}
      />

      <details
        id="editor-add-step"
        class="group rounded-2xl border border-dashed border-base-300 bg-base-100/50 p-4"
      >
        <summary class="flex cursor-pointer list-none items-center gap-2 font-semibold text-base-content/70 hover:text-primary transition-colors">
          <.icon name="hero-plus-circle" class="size-5" /> Add a step
          <.icon
            name="hero-chevron-down"
            class="ml-auto size-4 transition-transform group-open:rotate-180"
          />
        </summary>
        <div class="mt-4">
          <.cipher_grid
            id_prefix="editor-add-"
            event="add_step"
            icon="hero-plus-circle"
            ciphers={@ciphers}
          />
        </div>
      </details>
    </section>
    """
  end
end
