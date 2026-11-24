defmodule SubcipherWeb.PictureUpload.DetectionStatus do
  @moduledoc "Where the detection of symbols in the picture stands."
  use SubcipherWeb, :html

  attr :id, :string, required: true
  attr :detection, :map, required: true

  def detection_status(assigns) do
    ~H"""
    <div id={@id} class="text-sm min-h-5">
      <span :if={@detection.status == :detecting} class="text-base-content/70">
        Detecting symbols…
      </span>
      <span :if={@detection.status == :ready} class="text-success">
        <.icon name="hero-check-circle" class="size-4 align-text-bottom" />
        {length(@detection.glyphs)} symbols detected.
      </span>
      <span :if={@detection.status == :error} class="text-error">
        {@detection.message}
      </span>
    </div>
    """
  end
end
