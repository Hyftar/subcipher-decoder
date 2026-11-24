defmodule SubcipherWeb.PuzzleLive.Pictures.Controls do
  @moduledoc "Moves a picture earlier or later in the reading order of a puzzle."
  use SubcipherWeb, :html

  attr :section, :map, required: true
  attr :count, :integer, required: true, doc: "number of pictures in the puzzle"
  attr :id_prefix, :string, default: "", doc: "keeps ids unique when rendered twice"

  def picture_controls(assigns) do
    ~H"""
    <span class="flex items-center normal-case tracking-normal font-normal">
      <button
        type="button"
        id={"#{@id_prefix}move-up-#{@section.image.id}"}
        class="btn btn-ghost btn-sm btn-square"
        phx-click="move_image"
        phx-value-id={@section.image.id}
        phx-value-direction="up"
        disabled={@section.index == 1}
        aria-label={"Move picture #{@section.index} up"}
        title="Move up"
      >
        <.icon name="hero-arrow-up" class="size-5" />
      </button>
      <button
        type="button"
        id={"#{@id_prefix}move-down-#{@section.image.id}"}
        class="btn btn-ghost btn-sm btn-square"
        phx-click="move_image"
        phx-value-id={@section.image.id}
        phx-value-direction="down"
        disabled={@section.index == @count}
        aria-label={"Move picture #{@section.index} down"}
        title="Move down"
      >
        <.icon name="hero-arrow-down" class="size-5" />
      </button>
    </span>
    """
  end
end
