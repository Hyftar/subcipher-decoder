defmodule SubcipherWeb.PuzzleLive.FinalOutput do
  @moduledoc "The output of a puzzle's last step, shown below the other steps."
  use SubcipherWeb, :html

  import SubcipherWeb.Components.Output

  attr :puzzle, :any, required: true
  attr :last_step, :integer, required: true, doc: "number of the last step"
  attr :text, :string, required: true

  def final_output(assigns) do
    ~H"""
    <section
      id="final-output-block"
      class="rounded-2xl border border-base-300 bg-base-100 p-4 sm:p-6 space-y-2"
    >
      <h2 class="flex items-center justify-between text-sm font-semibold">
        Final output
        <.link
          patch={~p"/puzzles/#{@puzzle}?step=#{@last_step}"}
          class="link link-hover text-xs font-normal"
        >
          Go to step {@last_step} <.icon name="hero-arrow-right" class="size-3" />
        </.link>
      </h2>
      <.output id="final-output" text={@text} />
    </section>
    """
  end
end
