defmodule Subcipher.Steps.Ciphers.Anagram do
  @moduledoc """
  Anagram: the letters of the text were shuffled.

  The text becomes tiles: its letters (every non-space character) and
  `spaces` space tiles, 0 to letters − 1, so the solution can have another
  number of words than the clue. By default (`spaces` nil) there is one
  space tile per gap between the input's words, placed in the gaps.

  `order` is the order in which to read the tiles, as positions: "5,0,1"
  reads the 6th, 1st, then 2nd tile. Positions that don't exist (the input
  or the number of spaces changed) are dropped and tiles not placed yet
  follow in their original order. In the result, spaces next to each other
  count as one and spaces at either end are dropped.
  """
  use Subcipher.Steps.Cipher

  @impl true
  def type, do: "anagram"

  @impl true
  def name, do: "Anagram"

  @impl true
  def description,
    do: "The letters were shuffled: drag them (or tap two tiles) back into the right order."

  @impl true
  def osrs_usage,
    do:
      "Treasure Trails anagram clues: the solution is an NPC's name (words don't need to match)."

  @impl true
  def fields do
    [
      %{
        name: :spaces,
        type: :integer,
        control: :range,
        label: "Spaces",
        default: nil,
        min: 0,
        max: &max_spaces/1,
        auto: &input_spaces/1,
        help: "Number of word breaks in the solution (it doesn't have to match the clue)."
      },
      %{name: :order, type: :permutation, label: "Order of the characters", default: ""}
    ]
  end

  @impl true
  def validate(changeset) do
    changeset
    |> validate_number(:spaces, greater_than_or_equal_to: 0)
    |> validate_format(:order, ~r/^(\d+(,\d+)*)?$/, message: "must be positions like 2,0,1")
    |> validate_change(:order, fn :order, order ->
      positions = parse(order)
      if positions == Enum.uniq(positions), do: [], else: [order: "has repeated positions"]
    end)
  end

  @doc "Number of letters (non-space characters) of the input."
  def letter_count(text), do: text |> letters() |> length()

  @doc "Most spaces the solution can have: one less than the letters."
  def max_spaces(text), do: max(letter_count(text) - 1, 0)

  @doc "Number of spaces in the input: one per gap between its words."
  def input_spaces(text) do
    text
    |> String.trim()
    |> String.split(~r/\s+/u, trim: true)
    |> length()
    |> Kernel.-(1)
    |> max(0)
  end

  @doc "The number of space tiles: `spaces`, or the input's when nil, within range."
  def space_count(text, spaces) do
    (spaces || input_spaces(text)) |> min(max_spaces(text)) |> max(0)
  end

  @doc """
  The tiles of the input: its letters in order, with `space_count` space
  tiles placed in the gaps between its words, then any extra ones at the end.
  """
  def tiles(text, spaces \\ nil) do
    count = space_count(text, spaces)

    words = (text || "") |> String.trim() |> String.split(~r/\s+/u, trim: true)
    gaps = max(length(words) - 1, 0)

    {tiles, _} =
      words
      |> Enum.with_index()
      |> Enum.flat_map_reduce(count, fn {word, i}, left ->
        letters = String.graphemes(word)
        if i < gaps and left > 0, do: {letters ++ [" "], left - 1}, else: {letters, left}
      end)

    tiles ++ List.duplicate(" ", count - min(count, gaps))
  end

  defp letters(text), do: (text || "") |> String.graphemes() |> Enum.reject(&(&1 =~ ~r/^\s$/u))

  @doc """
  The full order of `count` tiles from a stored `order`: valid, unique
  positions first, then the missing ones in their original order.
  """
  def resolve_order(order, count) do
    placed = order |> parse() |> Enum.filter(&(&1 < count)) |> Enum.uniq()
    placed ++ (Enum.to_list(0..(count - 1)//1) -- placed)
  end

  defp parse(nil), do: []
  defp parse(""), do: []

  defp parse(order) do
    order |> String.split(",", trim: true) |> Enum.flat_map(&parse_int/1)
  end

  defp parse_int(s) do
    case Integer.parse(s) do
      {i, ""} when i >= 0 -> [i]
      _ -> []
    end
  end

  @impl true
  def decode(text, %{order: order} = params) do
    spaces = Map.get(params, :spaces)

    if parse(order) == [] and is_nil(spaces) do
      # Not rearranged yet: the text as it is.
      text
    else
      tiles = text |> tiles(spaces) |> List.to_tuple()

      order
      |> resolve_order(tuple_size(tiles))
      |> Enum.map_join(&elem(tiles, &1))
      |> String.split(" ", trim: true)
      |> Enum.join(" ")
    end
  end

  @impl true
  def summary(%{order: order}) do
    if parse(order) == [], do: nil, else: "Letters rearranged; Reset puts them back."
  end
end
