defmodule SubcipherWeb.AlgorithmLive.Trace.ImageSpec do
  @moduledoc """
  What the `.SymbolImage` hook draws: the pictures, and lines of tokens
  (glyph crops scaled to a common height, spaces, characters), with the
  image options.
  """
  alias SubcipherWeb.AlgorithmLive.KeyGlyph

  def build(%{algorithm: algorithm, tokens: tokens, options: options}) do
    lines =
      tokens
      |> Enum.chunk_by(&(&1 == {:char, "\n"}))
      |> Enum.reject(&(&1 == [{:char, "\n"}]))
      |> Enum.map(fn line -> Enum.map(line, &image_token(algorithm, &1)) end)

    Map.merge(options, %{
      images: Enum.map(algorithm.images, & &1["path"]),
      lines: lines,
      line_height: KeyGlyph.symbol_height() + 16
    })
  end

  defp image_token(algorithm, {:symbol, i}) do
    entry = Enum.at(algorithm.symbol_key, i)
    image = Enum.at(algorithm.images, entry["image"])
    scale = KeyGlyph.symbol_height() / max(image["glyph_height"] || entry["h"], 1)

    %{
      t: "glyph",
      i: entry["image"],
      x: entry["x"],
      y: entry["y"],
      w: entry["w"],
      h: entry["h"],
      scale: scale
    }
  end

  defp image_token(_algorithm, {:char, " "}), do: %{t: "space"}
  defp image_token(_algorithm, {:char, char}), do: %{t: "char", c: char}
  defp image_token(_algorithm, {:missing, letter}), do: %{t: "missing", c: letter}

  # Whether symbol tokens have anything to draw besides spaces and line
  # breaks (with nothing, the image would be an empty, unstyled box).
  def drawable?(tokens), do: Enum.any?(tokens, &(elem(&1, 0) != :char))
end
