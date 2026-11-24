defmodule SubcipherWeb.PuzzleLive.Pictures.AddPanel do
  @moduledoc "Adds a picture to a pictures puzzle (collapsible)."
  use SubcipherWeb, :html

  attr :puzzle, :any, required: true
  attr :current_scope, :any, required: true
  attr :show, :boolean, required: true, doc: "expanded"

  def add_picture_panel(assigns) do
    ~H"""
    <section id="add-picture" class="rounded-2xl border border-base-300 bg-base-100">
      <button
        type="button"
        phx-click="toggle_add"
        class="w-full flex items-center justify-between px-4 py-2 text-sm font-semibold"
      >
        <span class="flex items-center gap-2">
          <.icon name="hero-plus-circle" class="size-4" /> Add a picture to this cipher
        </span>
        <.icon
          name={if @show, do: "hero-chevron-up", else: "hero-chevron-down"}
          class="size-4"
        />
      </button>
      <div :if={@show} class="p-4 pt-0 space-y-3">
        <p class="text-sm text-base-content/70">
          Symbols in the new picture are matched with the ones you already have, so
          your letters apply to it right away.
        </p>
        <.live_component
          module={SubcipherWeb.PictureUploadComponent}
          id="add-picture-upload"
          puzzle={@puzzle}
          scope={@current_scope}
        />
      </div>
    </section>
    """
  end
end
