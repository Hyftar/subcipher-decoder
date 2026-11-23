defmodule Subcipher.Steps.Ciphers.Route do
  @moduledoc """
  Route cipher (a transposition, see
  https://crypto.interactive-maths.com/route-cipher.html): the plain text is
  written row by row into a grid of `width` columns, its last row filled with
  null letters, and the cipher text is read along a route through the grid:

    * `columns`: column after column, each in the same direction;
    * `zigzag`: column after column, alternately down and up;
    * `spiral_clockwise` / `spiral_anticlockwise`: inwards around the grid.

  Every route starts at `corner`. Encoding keeps the letters and digits
  only (no spaces or punctuation) and writes them in groups of five;
  decoding ignores whitespace, so cipher text in groups works, and a last
  row that isn't full is allowed. The trailing nulls are dropped from the
  decoded text.
  """
  use Subcipher.Steps.Cipher

  alias Subcipher.English

  @routes [
    {"Down / up the columns", "columns"},
    {"Zigzag through the columns", "zigzag"},
    {"Spiral inwards, clockwise", "spiral_clockwise"},
    {"Spiral inwards, anticlockwise", "spiral_anticlockwise"}
  ]

  @corners [
    {"Top left", "top_left"},
    {"Top right", "top_right"},
    {"Bottom right", "bottom_right"},
    {"Bottom left", "bottom_left"}
  ]

  # Widths tried by the suggestions.
  @max_suggested_width 20

  @impl true
  def type, do: "route"

  @impl true
  def name, do: "Route cipher"

  @impl true
  def description,
    do:
      "Written row by row in a grid, then read along a route through it: down the columns, zigzag or spiral."

  @impl true
  def fields do
    [
      %{
        name: :width,
        type: :integer,
        control: :range,
        label: "Width (columns)",
        default: 5,
        min: 2,
        max: &max_width/1
      },
      %{name: :route, type: :select, label: "Route", default: "columns", options: @routes},
      %{
        name: :corner,
        type: :select,
        label: "Starting corner",
        default: "top_left",
        options: @corners
      },
      %{
        name: :null,
        type: :string,
        label: "Null letter",
        default: "X",
        help: "Fills the last row of the grid when encoding; dropped from the end when decoding."
      }
    ]
  end

  @doc "The widest grid for `text`: one row (at least 2 columns)."
  def max_width(text), do: max(length(characters(text)), 2)

  @impl true
  def validate(changeset) do
    changeset
    |> validate_number(:width, greater_than_or_equal_to: 2)
    |> validate_length(:null, max: 1)
  end

  @impl true
  def summary(%{width: width, route: route, corner: corner}) do
    "#{width} columns · #{label(@routes, route)} from the #{String.downcase(label(@corners, corner))}"
  end

  @impl true
  def decode(text, params) do
    text
    |> characters()
    |> unroute(params)
    |> drop_nulls(params.null, params.width)
  end

  # The characters, read along the route, put back in the grid; read row by
  # row.
  defp unroute(chars, params) do
    width = params.width

    length(chars)
    |> route(width, params.route, params.corner)
    |> Enum.zip_with(chars, fn {row, col}, char -> {row * width + col, char} end)
    |> List.keysort(0)
    |> Enum.map_join(&elem(&1, 1))
  end

  @impl true
  def encode(text, params) do
    chars = for c <- String.graphemes(text), c =~ ~r/^[\p{L}\p{N}]$/u, do: c
    chars = pad(chars, params.null, params.width)

    grid =
      chars
      |> Enum.with_index()
      |> Map.new(fn {c, i} -> {{div(i, params.width), rem(i, params.width)}, c} end)

    route(length(chars), params.width, params.route, params.corner)
    |> Enum.map(&Map.fetch!(grid, &1))
    |> Enum.chunk_every(5)
    |> Enum.map_join(" ", &Enum.join/1)
  end

  # Tries every route from every corner for the widths up to
  # #{@max_suggested_width}, keeping the most English-like results (4-letter
  # sequences).
  @impl true
  def suggestions(input, _params) do
    chars = characters(input)
    n = length(chars)

    if n < 6 do
      []
    else
      candidates =
        for width <- 2..min(n - 1, @max_suggested_width)//1,
            {_, route} <- @routes,
            {_, corner} <- @corners do
          params = %{width: width, route: route, corner: corner, null: ""}
          output = unroute(chars, params)
          {English.score_per_quadgram(English.letters(output)) || -99.0, params, output}
        end

      tried = length(candidates)

      candidates
      |> Enum.sort_by(&elem(&1, 0), :desc)
      |> Enum.uniq_by(&elem(&1, 2))
      |> Enum.take(5)
      |> Enum.with_index(1)
      |> Enum.map(fn {{_score, params, _output}, rank} ->
        %{
          label: "#{params.width} columns, #{label(@routes, params.route) |> String.downcase()}",
          params: Map.delete(params, :null),
          reason: reason(params, n, rank, tried)
        }
      end)
    end
  end

  defp reason(params, n, rank, tried) do
    rows = div(n + params.width - 1, params.width)
    full = if rem(n, params.width) == 0, do: "full", else: "the last one not full"

    "#{rows} rows (#{full}), from the #{String.downcase(label(@corners, params.corner))}: " <>
      "#{ordinal(rank)} most English-like letter sequences of the #{tried} routes tried."
  end

  defp ordinal(1), do: "the"
  defp ordinal(2), do: "the 2nd"
  defp ordinal(3), do: "the 3rd"
  defp ordinal(n), do: "the #{n}th"

  ## Grid

  # The characters of the text in the grid: everything but whitespace.
  defp characters(text),
    do: text |> String.split(~r/\s+/u, trim: true) |> Enum.flat_map(&String.graphemes/1)

  defp pad(chars, null, width) when is_binary(null) and null != "" do
    missing = rem(width - rem(length(chars), width), width)
    chars ++ List.duplicate(null, missing)
  end

  defp pad(chars, _null, _width), do: chars

  # Trailing nulls, only within the last row (they were added to fill it).
  defp drop_nulls(text, null, width) when is_binary(null) and null != "" do
    chars = String.graphemes(text)
    null? = &(String.upcase(&1) == String.upcase(null))
    trailing = chars |> Enum.reverse() |> Enum.take_while(null?) |> length()
    chars |> Enum.drop(-min(trailing, width - 1)) |> Enum.join()
  end

  defp drop_nulls(text, _null, _width), do: text

  @doc """
  The cells `{row, column}` of a grid of `width` columns holding `n`
  characters (written row by row), in the order of `route` from `corner`.
  Cells past the last character (an incomplete last row) are skipped.
  """
  def route(0, _width, _route, _corner), do: []

  def route(n, width, route, corner) do
    rows = div(n + width - 1, width)

    route
    |> full_route(rows, width, corner)
    |> Enum.filter(fn {row, col} -> row * width + col < n end)
  end

  defp full_route(route, rows, width, corner) when route in ~w(columns zigzag) do
    {bottom?, right?} = corner_sides(corner)
    cols = if right?, do: (width - 1)..0//-1, else: 0..(width - 1)//1
    down = 0..(rows - 1)//1
    up = (rows - 1)..0//-1

    cols
    |> Enum.with_index()
    |> Enum.flat_map(fn {col, i} ->
      downwards = if route == "zigzag" and rem(i, 2) == 1, do: bottom?, else: not bottom?
      for row <- if(downwards, do: down, else: up), do: {row, col}
    end)
  end

  defp full_route(route, rows, width, corner)
       when route in ~w(spiral_clockwise spiral_anticlockwise) do
    clockwise = route == "spiral_clockwise"
    {bottom?, right?} = corner_sides(corner)
    start = {if(bottom?, do: rows - 1, else: 0), if(right?, do: width - 1, else: 0)}
    spiral(start, first_direction(corner, clockwise), clockwise, rows, width)
  end

  defp corner_sides("top_left"), do: {false, false}
  defp corner_sides("top_right"), do: {false, true}
  defp corner_sides("bottom_right"), do: {true, true}
  defp corner_sides("bottom_left"), do: {true, false}

  # Directions as {row step, column step}: along the edge, keeping the grid
  # on the inside of the turn.
  @right {0, 1}
  @left {0, -1}
  @down {1, 0}
  @up {-1, 0}

  defp first_direction("top_left", true), do: @right
  defp first_direction("top_right", true), do: @down
  defp first_direction("bottom_right", true), do: @left
  defp first_direction("bottom_left", true), do: @up
  defp first_direction("top_left", false), do: @down
  defp first_direction("top_right", false), do: @left
  defp first_direction("bottom_right", false), do: @up
  defp first_direction("bottom_left", false), do: @right

  # Walks straight on until the edge or a visited cell, then turns (right
  # when clockwise, left otherwise).
  defp spiral(start, direction, clockwise, rows, width) do
    total = rows * width

    Stream.unfold({start, direction, MapSet.new([start]), 1}, fn
      {_cell, _dir, _seen, count} when count > total ->
        nil

      {cell, dir, seen, count} ->
        next_state =
          if count == total do
            {cell, dir, seen, count + 1}
          else
            {next, dir} = step(cell, dir, clockwise, seen, rows, width)
            {next, dir, MapSet.put(seen, next), count + 1}
          end

        {cell, next_state}
    end)
    |> Enum.to_list()
  end

  defp step({row, col}, {dr, dc} = dir, clockwise, seen, rows, width) do
    next = {row + dr, col + dc}

    if free?(next, seen, rows, width) do
      {next, dir}
    else
      {tr, tc} = turned = if clockwise, do: {dc, -dr}, else: {-dc, dr}
      {{row + tr, col + tc}, turned}
    end
  end

  defp free?({row, col} = cell, seen, rows, width),
    do: row in 0..(rows - 1)//1 and col in 0..(width - 1)//1 and not MapSet.member?(seen, cell)

  defp label(options, value), do: options |> Enum.find(&(elem(&1, 1) == value)) |> elem(0)
end
