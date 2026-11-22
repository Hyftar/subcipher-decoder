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
  @default_threshold 0.040
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
  are numbered in order of first appearance in the input list. Glyphs may come
  from several pictures (`:image_id`); sizes are compared per picture.

  Options:
    * `:threshold` - maximum distance to join a cluster (default #{@default_threshold}).
  """
  def cluster(glyphs, opts \\ [])
  def cluster([], _opts), do: []

  def cluster(glyphs, opts) do
    threshold = Keyword.get(opts, :threshold, @default_threshold)
    roots = link(describe_all(glyphs), %{}, threshold)
    numbering = number_new_groups(roots)

    glyphs
    |> Enum.zip(roots)
    |> Enum.map(fn {g, root} -> Map.put(g, :cluster, Map.fetch!(numbering, root)) end)
  end

  @doc """
  Matches newly detected glyphs (e.g. from another picture of the same
  cipher) against `existing` glyphs, which carry a `:symbol_id`.

  Existing glyphs keep their symbol: user corrections (merges, splits) are
  respected. Each new glyph gets either the `:symbol_id` of the existing
  symbol it links to, or `symbol_id: nil` and a `:cluster` index (numbered
  by first appearance) grouping the new glyphs that match no existing symbol.

  Glyphs are compared per picture: sizes are relative to the typical glyph
  height of their own picture (`:image_id`), so pictures taken at different
  scales still match.
  """
  def match(new_glyphs, existing, opts \\ [])
  def match([], _existing, _opts), do: []

  def match(new_glyphs, existing, opts) do
    threshold = Keyword.get(opts, :threshold, @default_threshold)
    # Distinct image key for the new glyphs, so their size is measured
    # against their own picture.
    tagged = Enum.map(new_glyphs, &Map.put(&1, :image_id, {:new_image}))

    {new_items, existing_items} =
      tagged |> Kernel.++(existing) |> describe_all() |> Enum.split(length(tagged))

    seeds =
      existing
      |> Enum.zip(existing_items)
      |> Enum.reduce(%{}, fn {g, item}, seeds ->
        key = {:symbol, g.symbol_id}

        case seeds do
          %{^key => exemplars} ->
            Map.put(
              seeds,
              key,
              add_exemplar(exemplars, item, min_distance(exemplars, item), threshold)
            )

          _ ->
            Map.put(seeds, key, [item])
        end
      end)

    roots = link(new_items, seeds, threshold)
    numbering = number_new_groups(roots)

    new_glyphs
    |> Enum.zip(roots)
    |> Enum.map(fn
      {g, {:symbol, id}} -> Map.merge(g, %{symbol_id: id, cluster: nil})
      {g, root} -> Map.merge(g, %{symbol_id: nil, cluster: Map.fetch!(numbering, root)})
    end)
  end

  # Describes glyphs, measuring sizes against the median glyph height of
  # their own picture (`:image_id`, absent for a single fresh detection).
  defp describe_all(glyphs) do
    ref_hs =
      glyphs
      |> Enum.group_by(&Map.get(&1, :image_id))
      |> Map.new(fn {image, gs} -> {image, median(Enum.map(gs, & &1.h))} end)

    Enum.map(glyphs, &describe(&1, Map.fetch!(ref_hs, Map.get(&1, :image_id))))
  end

  # Greedy single linkage. A glyph joins the group with the closest member
  # (not the closest average), so small variations between copies of a
  # symbol (resampling, noise) can chain. Each group keeps a few varied
  # exemplars rather than every member, to stay fast.
  #
  # `seeds` are pre-existing groups (`{:symbol, id} => exemplars`); new
  # groups are keyed `{:new, n}`. Seeds are never merged together. Returns
  # the root group key of every item.
  defp link(items, seeds, threshold) do
    {assignments, groups} =
      items
      |> Enum.with_index()
      |> Enum.map_reduce(seeds, fn {item, i}, groups ->
        case closest_group(groups, item, threshold) do
          nil ->
            {{:new, i}, Map.put(groups, {:new, i}, [item])}

          {key, d} ->
            {key, Map.update!(groups, key, &add_exemplar(&1, item, d, threshold))}
        end
      end)

    # Join groups that ended up within reach of each other (a glyph close to
    # two groups only joined one of them).
    root = link_groups(groups, threshold)
    Enum.map(assignments, &Map.fetch!(root, &1))
  end

  # Numbers the new (non-seed) groups by first appearance.
  defp number_new_groups(roots) do
    roots
    |> Enum.reject(&match?({:symbol, _}, &1))
    |> Enum.uniq()
    |> Enum.with_index()
    |> Map.new()
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

  @max_exemplars 32

  defp closest_group(groups, item, threshold) do
    groups
    |> Enum.map(fn {id, exemplars} -> {id, min_distance(exemplars, item)} end)
    |> Enum.filter(fn {_, d} -> d <= threshold end)
    |> Enum.min_by(&elem(&1, 1), fn -> nil end)
  end

  defp min_distance(exemplars, item) do
    exemplars |> Enum.map(&distance(&1, item)) |> Enum.min()
  end

  # Only glyphs that look noticeably different from the existing exemplars
  # are kept, so the exemplars cover the variations of the symbol.
  defp add_exemplar(exemplars, item, d, threshold) do
    if d > threshold / 6 and length(exemplars) < @max_exemplars,
      do: exemplars ++ [item],
      else: exemplars
  end

  # Single-linkage between groups: returns %{group_key => root_group_key}.
  # Two seed groups (existing symbols) are never joined; when a new group
  # joins a seed, the seed is the root.
  defp link_groups(groups, threshold) do
    keys = groups |> Map.keys() |> Enum.sort()
    parents = Map.new(keys, &{&1, &1})

    parents =
      for a <- keys, b <- keys, a < b, reduce: parents do
        parents ->
          ra = find_root(parents, a)
          rb = find_root(parents, b)

          cond do
            ra == rb -> parents
            seed?(ra) and seed?(rb) -> parents
            not linked?(groups[a], groups[b], threshold) -> parents
            seed?(rb) or (not seed?(ra) and rb < ra) -> Map.put(parents, ra, rb)
            true -> Map.put(parents, rb, ra)
          end
      end

    Map.new(keys, &{&1, find_root(parents, &1)})
  end

  defp seed?(key), do: match?({:symbol, _}, key)

  # Two groups are joined when the members of the smaller one are, on
  # average, within reach of the other group. A single coincidental close
  # pair (e.g. a blurry photo of a symbol resembling a sharp scan of
  # another) is not enough to chain two symbols together.
  defp linked?(xs, ys, threshold) do
    {small, big} = if length(xs) <= length(ys), do: {xs, ys}, else: {ys, xs}
    Enum.sum_by(small, &min_distance(big, &1)) / length(small) <= threshold
  end

  defp find_root(parents, id) do
    case Map.fetch!(parents, id) do
      ^id -> id
      parent -> find_root(parents, parent)
    end
  end

  defp median([]), do: 0
  defp median(values), do: values |> Enum.sort() |> Enum.at(div(length(values), 2))
end
