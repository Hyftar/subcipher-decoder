defmodule SubcipherWeb.PuzzleLive.Pictures.AddPanel do
  @moduledoc "Adds a picture to a pictures puzzle (collapsible)."
  use SubcipherWeb, :html

  import SubcipherWeb.Components.Accordion

  attr :puzzle, :any, required: true
  attr :current_scope, :any, required: true

  def add_picture_panel(assigns) do
    ~H"""
    <.accordion id="add-picture" icon="hero-plus-circle">
      <:title>Add a picture to this cipher</:title>
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
    </.accordion>
    """
  end
end
