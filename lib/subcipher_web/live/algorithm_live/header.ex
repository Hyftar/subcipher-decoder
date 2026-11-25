defmodule SubcipherWeb.AlgorithmLive.Header do
  @moduledoc """
  The title of an algorithm, with its actions (visibility, delete…); for an
  opened cipher (a draft), a link to save it.
  """
  use SubcipherWeb, :html

  import SubcipherWeb.Components.VisibilityToggle

  attr :algorithm, :any, required: true
  attr :editing, :boolean, required: true
  attr :owner, :boolean, required: true, doc: "the current user owns the algorithm"
  attr :draft, :boolean, default: false, doc: "an opened cipher, not saved"
  attr :current_scope, :any, default: nil

  def algorithm_header(assigns) do
    ~H"""
    <div class="flex flex-wrap items-center gap-3">
      <.link navigate={~p"/"} class="btn btn-ghost btn-square" aria-label="Back">
        <.icon name="hero-arrow-left" class="size-6" />
      </.link>
      <div class="flex-1 min-w-48">
        <p
          :if={@draft}
          id="draft-label"
          class="flex items-center gap-2 text-xs font-semibold uppercase tracking-wider text-primary"
        >
          Cipher
          <span class="rounded-full bg-base-200 px-2 py-0.5 text-[10px] font-medium normal-case tracking-normal text-base-content/60">
            Not saved
          </span>
        </p>
        <p :if={!@draft} class="text-xs font-semibold uppercase tracking-wider text-primary">
          Algorithm
        </p>
        <form
          :if={@editing and !@draft}
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
        <h1 :if={!@editing or @draft} class="text-2xl font-bold tracking-tight">
          {@algorithm.title}
        </h1>
      </div>
      <a
        :if={@draft}
        href="#save-draft"
        id="jump-to-save"
        class={[
          "btn",
          if(@current_scope, do: "btn-primary btn-soft", else: "btn-ghost")
        ]}
      >
        <.icon
          name={if @current_scope, do: "hero-bookmark", else: "hero-lock-closed"}
          class="size-5"
        />
        {if @current_scope, do: "Save as puzzle", else: "Log in to save"}
      </a>
      <.link
        :if={@owner and !@draft and @algorithm.source_puzzle_id}
        navigate={~p"/puzzles/#{@algorithm.source_puzzle_id}"}
        class="btn btn-ghost"
        id="source-puzzle"
      >
        <.icon name="hero-puzzle-piece" class="size-5" /> Puzzle
      </.link>
      <.visibility_toggle :if={@owner and !@draft} public={@algorithm.public} />
      <button
        :if={@owner and !@draft}
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
