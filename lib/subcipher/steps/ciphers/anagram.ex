defmodule Subcipher.Steps.Ciphers.Anagram do
  @moduledoc """
  Anagram: the characters of the text were shuffled. The `order` parameter
  is the order in which to read the input's characters (spaces included),
  as positions: "5,0,1" reads the 6th, 1st, then 2nd character. Positions
  that don't exist (the input changed) are dropped and characters not
  placed yet follow in their original order. The result is trimmed, so
  spaces dragged to the end disappear.
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
    [%{name: :order, type: :permutation, label: "Order of the characters", default: ""}]
  end

  @impl true
  def validate(changeset) do
    changeset
    |> validate_format(:order, ~r/^(\d+(,\d+)*)?$/, message: "must be positions like 2,0,1")
    |> validate_change(:order, fn :order, order ->
      positions = parse(order)
      if positions == Enum.uniq(positions), do: [], else: [order: "has repeated positions"]
    end)
  end

  @doc "The characters (graphemes) of the input that can be reordered."
  def tiles(text), do: String.graphemes(text || "")

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
  def decode(text, %{order: order}) do
    case parse(order) do
      # Not rearranged yet: the text as it is.
      [] ->
        text

      _ ->
        tiles = text |> tiles() |> List.to_tuple()

        order
        |> resolve_order(tuple_size(tiles))
        |> Enum.map_join(&elem(tiles, &1))
        |> String.trim()
    end
  end

  @impl true
  def summary(%{order: order}) do
    if parse(order) == [], do: nil, else: "Letters rearranged; Reset puts them back."
  end
end
