defmodule Subcipher.Ciphers.Analysis do
  @moduledoc """
  Turns the raw glyphs detected in a picture (bounding boxes + a 16x16 ink
  coverage grid, see `assets/js/glyph_detector.js`) into cipher text:

    * `layout/1` orders glyphs in reading order, splits them in lines and
      detects word breaks;
    * `cluster/2` groups glyphs that look the same into symbols.

  Everything here is pure so it can be tested without a browser.
  """

  @grid_bytes 256
  @default_threshold 0.038
  @aspect_weight 0.1
  @size_weight 0.1

  def default_threshold, do: @default_threshold

  @type glyph :: %{
          required(:x) => non_neg_integer(),
          required(:y) => non_neg_integer(),
          required(:w) => pos_integer(),
          required(:h) => pos_integer(),
          required(:features) => binary(),
          optional(atom()) => term()
        }

  @doc """
  Validates and normalizes the payload sent by the browser.

  Returns `{:ok, glyphs}` or `{:error, reason}`.
  """
  def parse_detection(%{"glyphs" => glyphs}) when is_list(glyphs) and glyphs != [] do
    glyphs
    |> Enum.reduce_while([], fn raw, acc ->
      case parse_glyph(raw) do
        {:ok, g} -> {:cont, [g | acc]}
        :error -> {:halt, :error}
      end
    end)
    |> case do
      :error -> {:error, :invalid_glyph}
      parsed -> {:ok, Enum.reverse(parsed)}
    end
  end

  def parse_detection(%{"glyphs" => []}), do: {:error, :no_glyphs}
  def parse_detection(_), do: {:error, :invalid_payload}

  defp parse_glyph(%{"x" => x, "y" => y, "w" => w, "h" => h, "f" => f})
       when is_integer(x) and is_integer(y) and is_integer(w) and is_integer(h) and
              x >= 0 and y >= 0 and w > 0 and h > 0 and is_binary(f) do
    case Base.decode64(f) do
      {:ok, <<_::binary-size(@grid_bytes)>> = features} ->
        {:ok, %{x: x, y: y, w: w, h: h, features: features}}

      _ ->
        :error
    end
  end

  defp parse_glyph(_), do: :error

  @doc """
  Full pipeline: layout then clustering.

  Returns glyphs in reading order, each with `:line`, `:position`,
  `:space_before` and `:cluster` (0-based, numbered by first appearance).
  """
  def analyze(glyphs, opts \\ []) do
    glyphs |> layout() |> cluster(opts)
  end

  @doc """
  Sorts glyphs in reading order (top to bottom, left to right), assigning a
  `:line` index, a global `:position` and a `:space_before` flag.
  """
  def layout([]), do: []

  def layout(glyphs) do
    ref_h = median(Enum.map(glyphs, & &1.h))

    lines =
      glyphs
      |> Enum.sort_by(&center_y/1)
      |> Enum.reduce([], fn g, lines -> place_in_line(lines, g, ref_h) end)
      |> Enum.map(fn line -> Enum.sort_by(line.glyphs, & &1.x) end)
      |> Enum.sort_by(fn line -> line |> Enum.map(&center_y/1) |> median() end)

    gaps =
      Enum.flat_map(lines, fn line ->
        line |> Enum.chunk_every(2, 1, :discard) |> Enum.map(fn [a, b] -> gap(a, b) end)
      end)

    space_threshold = max(0.3 * ref_h, 2.0 * median(gaps))

    lines
    |> Enum.with_index()
    |> Enum.flat_map(fn {line, line_no} ->
      [nil | line]
      |> Enum.chunk_every(2, 1, :discard)
      |> Enum.map(fn [prev, g] ->
        Map.merge(g, %{
          line: line_no,
          space_before: prev != nil and gap(prev, g) > space_threshold
        })
      end)
    end)
    |> Enum.with_index()
    |> Enum.map(fn {g, i} -> Map.put(g, :position, i) end)
  end

  defp place_in_line(lines, g, ref_h) do
    cy = center_y(g)

    best =
      lines
      |> Enum.with_index()
      |> Enum.map(fn {line, i} -> {abs(line.cy - cy), i} end)
      |> Enum.filter(fn {dist, _} -> dist <= 0.6 * ref_h end)
      |> Enum.min_by(&elem(&1, 0), fn -> nil end)

    case best do
      nil ->
        [%{cy: cy, glyphs: [g]} | lines]

      {_, i} ->
        List.update_at(lines, i, fn line ->
          n = length(line.glyphs)
          %{cy: (line.cy * n + cy) / (n + 1), glyphs: [g | line.glyphs]}
        end)
    end
  end

  defp center_y(g), do: g.y + g.h / 2
  defp gap(a, b), do: b.x - (a.x + a.w)

  @doc """
  Groups glyphs that look alike. Each glyph gets a `:cluster` index; clusters
  are numbered in order of first appearance in the input list.

  Options:
    * `:threshold` - maximum distance to join a cluster (default #{@default_threshold}).
  """
  def cluster(glyphs, opts \\ [])
  def cluster([], _opts), do: []

  def cluster(glyphs, opts) do
    threshold = Keyword.get(opts, :threshold, @default_threshold)
    ref_h = median(Enum.map(glyphs, & &1.h))
    items = Enum.map(glyphs, &describe(&1, ref_h))

    # Pass 1: greedy leader clustering.
    clusters =
      Enum.reduce(items, [], fn item, clusters ->
        case nearest(clusters, item, threshold) do
          nil -> clusters ++ [new_cluster(item)]
          i -> List.update_at(clusters, i, &add_to_cluster(&1, item))
        end
      end)

    # Pass 2: reassign every glyph to its closest centroid, fixing glyphs
    # that joined a cluster before its centroid settled.
    centroids = Enum.map(clusters, &centroid/1)

    assignments =
      Enum.map(items, fn item ->
        centroids
        |> Enum.with_index()
        |> Enum.min_by(fn {c, _} -> distance(c, item) end)
        |> elem(1)
      end)

    # Renumber by first appearance (some clusters may have emptied).
    {numbering, _} =
      Enum.reduce(assignments, {%{}, 0}, fn a, {map, next} ->
        if Map.has_key?(map, a), do: {map, next}, else: {Map.put(map, a, next), next + 1}
      end)

    glyphs
    |> Enum.zip(assignments)
    |> Enum.map(fn {g, a} -> Map.put(g, :cluster, Map.fetch!(numbering, a)) end)
  end

  @doc """
  Distance between two glyph descriptions, roughly in `[0, 1+]`.
  Combines the shape difference with differences in aspect ratio and size.
  """
  def distance(a, b) do
    # Cosine distance between the (smoothed) coverage grids: insensitive to
    # stroke darkness/thickness, sensitive to where the ink is.
    dot = Enum.zip_reduce(a.grid, b.grid, 0, fn x, y, acc -> acc + x * y end)
    shape = 1 - dot / max(a.norm * b.norm, 1.0e-9)

    shape + @aspect_weight * abs(:math.log(a.aspect / b.aspect)) +
      @size_weight * abs(:math.log(a.size / b.size))
  end

  defp with_norm(desc) do
    Map.put(desc, :norm, :math.sqrt(Enum.reduce(desc.grid, 0, fn v, acc -> acc + v * v end)))
  end

  @doc false
  def describe(g, ref_h) do
    %{
      grid: g.features |> :binary.bin_to_list() |> smooth(),
      aspect: g.w / g.h,
      size: max(g.w, g.h) / max(ref_h, 1)
    }
    |> with_norm()
  end

  @side 16
  @kernel for dy <- -1..1, dx <- -1..1, do: {dx, dy, :math.exp(-(dx * dx + dy * dy) / 2)}

  # 3x3 gaussian blur of the coverage grid, so a glyph shifted by a pixel (a
  # slightly different crop of the same symbol) still matches its siblings.
  defp smooth(grid) do
    t = List.to_tuple(grid)

    for y <- 0..(@side - 1), x <- 0..(@side - 1) do
      {sum, weight} =
        for {dx, dy, k} <- @kernel,
            yy = y + dy,
            xx = x + dx,
            yy in 0..(@side - 1) and xx in 0..(@side - 1),
            reduce: {0, 0} do
          {s, w} -> {s + k * elem(t, yy * @side + xx), w + k}
        end

      sum / weight
    end
  end

  defp nearest(clusters, item, threshold) do
    clusters
    |> Enum.with_index()
    |> Enum.map(fn {c, i} -> {distance(centroid(c), item), i} end)
    |> Enum.filter(fn {d, _} -> d <= threshold end)
    |> Enum.min_by(&elem(&1, 0), fn -> nil end)
    |> case do
      nil -> nil
      {_, i} -> i
    end
  end

  defp new_cluster(item), do: %{n: 1, grid: item.grid, aspect: item.aspect, size: item.size}

  defp add_to_cluster(c, item) do
    %{
      n: c.n + 1,
      grid: Enum.zip_with(c.grid, item.grid, &+/2),
      aspect: c.aspect + item.aspect,
      size: c.size + item.size
    }
  end

  defp centroid(%{n: n} = c) do
    %{grid: Enum.map(c.grid, &(&1 / n)), aspect: c.aspect / n, size: c.size / n}
    |> with_norm()
  end

  defp median([]), do: 0
  defp median(values), do: values |> Enum.sort() |> Enum.at(div(length(values), 2))
end
