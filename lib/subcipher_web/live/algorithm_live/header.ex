defmodule SubcipherWeb.AlgorithmLive.Header do
  @moduledoc "The title of an algorithm, with its actions (visibility, delete…)."
  use SubcipherWeb, :html

  import SubcipherWeb.Components.VisibilityToggle

  attr :algorithm, :any, required: true
  attr :editing, :boolean, required: true
  attr :owner, :boolean, required: true, doc: "the current user owns the algorithm"

  def algorithm_header(assigns) do
    ~H"""
    <div class="flex flex-wrap items-center gap-3">
      <.link navigate={~p"/"} class="btn btn-ghost btn-square" aria-label="Back">
        <.icon name="hero-arrow-left" class="size-6" />
      </.link>
      <div class="flex-1 min-w-48">
        <p class="text-xs font-semibold uppercase tracking-wider text-primary">Algorithm</p>
        <form
          :if={@editing}
          id="title-form"
          phx-submit="rename"
          phx-change="rename"
          class="mt-0.5"
        >
          <input
            type="text"
            id="algorithm-title"
            name="title"
            value={@algorithm.title}
            phx-debounce="500"
            maxlength="120"
            aria-label="Title"
            class="input input-ghost w-full -ml-3 px-3 text-2xl font-bold tracking-tight focus:bg-base-200/60"
          />
        </form>
        <h1 :if={!@editing} class="text-2xl font-bold tracking-tight">{@algorithm.title}</h1>
      </div>
      <.link
        :if={@owner and @algorithm.source_puzzle_id}
        navigate={~p"/puzzles/#{@algorithm.source_puzzle_id}"}
        class="btn btn-ghost"
        id="source-puzzle"
      >
        <.icon name="hero-puzzle-piece" class="size-5" /> Puzzle
      </.link>
      <.visibility_toggle :if={@owner} public={@algorithm.public} />
      <button
        :if={@owner}
        type="button"
        id="delete-algorithm"
        class="btn btn-ghost"
        phx-click="delete"
        data-confirm="Delete this algorithm?"
      >
        <.icon name="hero-trash" class="size-5" /> Delete
      </button>
    </div>
    """
  end
end
