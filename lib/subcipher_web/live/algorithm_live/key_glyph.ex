defmodule SubcipherWeb.AlgorithmLive.KeyGlyph do
  @moduledoc """
  A symbol of an algorithm's key, cropped from its picture with CSS. Each
  glyph is scaled to fill the same square (its longer side at full size) and
  centred in it, so all symbols look about the same size, whatever their
  size in the picture.
  """
  use SubcipherWeb, :html

  # Height (px) of the symbols drawn from the symbol key.
  @symbol_height 36

  # Margin (px, in the picture) kept around each glyph's box.
  @pad 2

  @doc "Height (px) of the symbols drawn from the symbol key."
  def symbol_height, do: @symbol_height

  attr :algorithm, :any, required: true
  attr :entry, :map, required: true

  def key_glyph(assigns) do
    %{algorithm: algorithm, entry: entry} = assigns
    image = Enum.at(algorithm.images, entry["image"])
    w = entry["w"] + 2 * @pad
    h = entry["h"] + 2 * @pad
    scale = @symbol_height / max(max(w, h), 1)

    # The crop only: the square around it stays empty (a background as large
    # as the square would show the neighbouring glyphs of the picture).
    crop =
      Enum.join(
        [
          "width: #{px(w * scale)}",
          "height: #{px(h * scale)}",
          "background-image: url('#{image["path"]}')",
          "background-size: #{px(image["width"] * scale)} #{px(image["height"] * scale)}",
          "background-position: #{px(-(entry["x"] - @pad) * scale)} #{px(-(entry["y"] - @pad) * scale)}"
        ],
        "; "
      )

    assigns =
      assign(assigns,
        crop: crop,
        square: "width: #{px(@symbol_height)}; height: #{px(@symbol_height)}"
      )

    ~H"""
    <span class="grid place-items-center shrink-0" style={@square} aria-hidden="true">
      <span class="block bg-no-repeat rounded-sm" style={@crop}></span>
    </span>
    """
  end

  defp px(v), do: "#{Float.round(v * 1.0, 2)}px"
end
