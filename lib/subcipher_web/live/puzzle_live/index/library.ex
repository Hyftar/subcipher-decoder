defmodule SubcipherWeb.PuzzleLive.Index.Library do
  @moduledoc """
  The user's puzzles and algorithms (with the creation of an algorithm),
  and the ones others shared.
  """
  use SubcipherWeb, :html

  alias Subcipher.Algorithms

  import SubcipherWeb.Components.CipherGrid
  import SubcipherWeb.PuzzleLive.Index.{AlgorithmItem, PuzzleItem}

  attr :current_scope, :any, required: true
  attr :puzzles, :list, required: true, doc: "the user's"
  attr :algorithms, :list, required: true, doc: "the user's"
  attr :public_puzzles, :list, required: true, doc: "shared by others"
  attr :public_algorithms, :list, required: true, doc: "shared by others"
  attr :new_algorithm, :boolean, required: true, doc: "choosing the cipher of a new algorithm"

  def library(assigns) do
    ~H"""
    <aside class="space-y-3">
      <%= if @current_scope do %>
        <h2 class="font-semibold text-base-content/80">Your puzzles</h2>
        <p :if={@puzzles == []} class="text-sm text-base-content/60">
          No puzzles yet. Choose a cipher to get started.
        </p>
        <ul id="puzzles" class="space-y-2">
          <.puzzle_item :for={row <- @puzzles} row={row} owned />
        </ul>

        <div class="flex items-center justify-between gap-2 pt-4">
          <h2 class="font-semibold text-base-content/80">Your algorithms</h2>
          <button
            type="button"
            id="new-algorithm"
            class={["btn", if(@new_algorithm, do: "btn-active", else: "btn-ghost")]}
            phx-click="toggle_new_algorithm"
            aria-expanded={to_string(@new_algorithm)}
          >
            <.icon name="hero-plus" class="size-5" /> New
          </button>
        </div>
        <div :if={@new_algorithm} id="new-algorithm-panel" class="space-y-2">
          <p class="text-sm text-base-content/60">
            Its first step (more can be added after):
          </p>
          <.cipher_grid
            id_prefix="new-algorithm-"
            event="create_algorithm"
            icon="hero-plus-circle"
            class="grid-cols-1"
            ciphers={Algorithms.ciphers()}
          />
        </div>
        <p :if={@algorithms == [] and !@new_algorithm} class="text-sm text-base-content/60">
          None yet: create one with <strong>New</strong>, or on a puzzle, "Make an algorithm"
          turns its steps into one, to encode and decode any text.
        </p>
        <ul id="algorithms" class="space-y-2">
          <.algorithm_item :for={algorithm <- @algorithms} algorithm={algorithm} owned />
        </ul>
      <% end %>

      <div
        :if={@public_puzzles != [] or @public_algorithms != []}
        id="public"
        class={["space-y-3", @current_scope && "pt-4"]}
      >
        <h2 class="flex items-center gap-2 font-semibold text-base-content/80">
          <.icon name="hero-globe-alt" class="size-5 text-base-content/50" /> Shared by others
        </h2>
        <ul :if={@public_puzzles != []} id="public-puzzles" class="space-y-2">
          <.puzzle_item :for={row <- @public_puzzles} row={row} />
        </ul>
        <ul :if={@public_algorithms != []} id="public-algorithms" class="space-y-2">
          <.algorithm_item :for={algorithm <- @public_algorithms} algorithm={algorithm} />
        </ul>
      </div>
    </aside>
    """
  end
end
