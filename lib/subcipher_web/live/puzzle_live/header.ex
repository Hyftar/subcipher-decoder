defmodule SubcipherWeb.PuzzleLive.Header do
  @moduledoc "The title of a puzzle, its progress and its actions."
  use SubcipherWeb, :html

  alias Subcipher.Ciphers.Puzzle

  import SubcipherWeb.Components.VisibilityToggle

  attr :puzzle, :any, required: true
  attr :title_form, :any, required: true
  attr :owner, :boolean, required: true, doc: "the current user owns the puzzle"
  attr :solved, :integer, required: true, doc: "symbols with a letter"
  attr :symbol_count, :integer, required: true, doc: "symbols not ignored"

  def puzzle_header(assigns) do
    ~H"""
    <div class="flex flex-wrap items-center gap-3">
      <.link navigate={~p"/"} class="btn btn-ghost btn-square" aria-label="Back">
        <.icon name="hero-arrow-left" class="size-6" />
      </.link>
      <%= if @owner do %>
        <.form
          for={@title_form}
          id="title-form"
          phx-submit="rename"
          class="flex-1 min-w-48"
        >
          <input
            type="text"
            name={@title_form[:title].name}
            value={@title_form[:title].value}
            phx-blur="rename_blur"
            aria-label="Title"
            class="w-full bg-transparent text-2xl font-bold tracking-tight rounded-md px-1 -mx-1 focus:outline-none focus:ring-2 focus:ring-primary/40"
          />
        </.form>
      <% else %>
        <h1 class="flex-1 min-w-48 text-2xl font-bold tracking-tight">{@puzzle.title}</h1>
      <% end %>
      <div :if={Puzzle.pictures?(@puzzle)} class="flex items-center gap-3 text-sm">
        <span class="text-base-content/70" id="progress">
          {@solved} / {@symbol_count} symbols
        </span>
        <progress class="progress progress-primary w-32" value={@solved} max={@symbol_count} />
      </div>
      <.visibility_toggle :if={@owner} public={@puzzle.public} />
      <button
        :if={@owner}
        type="button"
        id="make-algorithm"
        class="btn btn-soft btn-primary"
        phx-click="make_algorithm"
        title="Copy these steps into an algorithm to encode and decode any text"
      >
        <.icon name="hero-cog-6-tooth" class="size-5" /> Make an algorithm
      </button>
    </div>
    """
  end
end
