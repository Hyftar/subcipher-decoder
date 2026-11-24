defmodule SubcipherWeb.PuzzleLive.Sections do
  @moduledoc """
  The cipher text of a pictures puzzle laid out for display: one section per
  picture, its glyphs in lines and words. Each picture gets its own display
  scale so that glyphs from pictures taken at different sizes look alike.
  """

  # Height (px) at which the typical glyph is displayed in the cipher text.
  @display_height 40

  @doc "`%{image, index, glyphs, lines, scale}` for each picture of `puzzle`."
  def build(puzzle) do
    by_image = Enum.group_by(puzzle.glyphs, & &1.image_id)

    for {image, index} <- Enum.with_index(puzzle.images, 1) do
      glyphs = Map.get(by_image, image.id, [])

      %{
        image: image,
        index: index,
        glyphs: glyphs,
        lines: lines(glyphs),
        scale: @display_height / max(median(Enum.map(glyphs, & &1.h)), 1)
      }
    end
  end

  # Lines -> words -> glyphs, with each line's vertical extent so glyphs can
  # keep their position relative to the baseline.
  defp lines([]), do: []

  defp lines(glyphs) do
    glyphs
    |> Enum.chunk_by(& &1.line)
    |> Enum.map(fn line ->
      top = line |> Enum.map(& &1.y) |> Enum.min()
      bottom = line |> Enum.map(&(&1.y + &1.h)) |> Enum.max()

      words =
        Enum.chunk_while(
          line,
          [],
          fn g, acc ->
            if g.space_before and acc != [],
              do: {:cont, Enum.reverse(acc), [g]},
              else: {:cont, [g | acc]}
          end,
          fn acc -> {:cont, Enum.reverse(acc), []} end
        )

      %{id: "#{hd(line).image_id}-#{hd(line).line}", top: top, height: bottom - top, words: words}
    end)
  end

  defp median([]), do: 0
  defp median(values), do: values |> Enum.sort() |> Enum.at(div(length(values), 2))
end
