defmodule SubcipherWeb.PuzzleLive.GlyphImage do
  @moduledoc "A glyph of a puzzle, cropped from its picture with CSS."
  use SubcipherWeb, :html

  attr :glyph, :any, required: true
  attr :image, :any, required: true, doc: "the picture the glyph comes from"
  attr :scale, :float, default: nil, doc: "explicit display scale"
  attr :box, :integer, default: nil, doc: "fit the glyph in a square of this size (px)"

  def glyph_image(assigns) do
    %{glyph: g, image: image} = assigns
    pad = 2
    w = g.w + 2 * pad
    h = g.h + 2 * pad
    scale = assigns.scale || assigns.box / max(w, h)

    style =
      [
        "width: #{px(w * scale)}",
        "height: #{px(h * scale)}",
        "background-image: url('#{image.path}')",
        "background-size: #{px(image.width * scale)} #{px(image.height * scale)}",
        "background-position: #{px(-(g.x - pad) * scale)} #{px(-(g.y - pad) * scale)}"
      ]
      |> Enum.join("; ")

    assigns = assign(assigns, style: style)

    ~H"""
    <span class="block bg-no-repeat rounded-sm" style={@style} aria-hidden="true"></span>
    """
  end

  defp px(v), do: "#{Float.round(v * 1.0, 2)}px"
end
