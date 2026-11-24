defmodule SubcipherWeb.PuzzleLive.Index.AlgorithmItem do
  @moduledoc "An algorithm in a list: its title and steps."
  use SubcipherWeb, :html

  alias Subcipher.Steps

  attr :algorithm, :any, required: true
  attr :owned, :boolean, default: false

  def algorithm_item(assigns) do
    ~H"""
    <li id={if @owned, do: "algorithm-#{@algorithm.id}", else: "public-algorithm-#{@algorithm.id}"}>
      <.link
        navigate={~p"/algorithms/#{@algorithm}"}
        class="flex items-center gap-3 rounded-xl border border-base-300 bg-base-100 p-2 pr-3 transition hover:border-primary/50 hover:shadow-sm"
      >
        <span class="grid place-items-center size-10 rounded-lg bg-primary/10 text-primary shrink-0">
          <.icon name="hero-cog-6-tooth" class="size-5" />
        </span>
        <span class="min-w-0">
          <span class="flex items-center gap-1.5 font-medium">
            <span class="truncate">{@algorithm.title}</span>
            <.icon
              :if={@owned and @algorithm.public}
              name="hero-globe-alt"
              class="size-4 shrink-0 text-primary"
            />
          </span>
          <span class="block text-xs text-base-content/60">
            {algorithm_steps(@algorithm)}
          </span>
        </span>
      </.link>
    </li>
    """
  end

  defp algorithm_steps(algorithm) do
    names = Enum.map(algorithm.steps, &Steps.cipher!(&1["type"]).name())

    names =
      if algorithm.input_kind == "pictures", do: ["Symbol substitution" | names], else: names

    Enum.join(names, " → ")
  end
end
