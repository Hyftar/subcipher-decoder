defmodule Subcipher.Steps.Ciphers.LetterSubstitution do
  @moduledoc """
  Free letter-to-letter substitution, filled in by hand: each cipher letter
  is mapped to a plain letter. Unmapped letters are shown as "·".
  """
  use Subcipher.Steps.Cipher

  @impl true
  def type, do: "letter_substitution"

  @impl true
  def name, do: "Letter substitution"

  @impl true
  def description,
    do: "Map each letter to another one by hand, like the symbols of step 1."

  @impl true
  def fields do
    [%{name: :mapping, type: :letter_map, label: "Cipher letter → plain letter", default: %{}}]
  end

  @impl true
  def validate(changeset) do
    changeset
    |> update_change(:mapping, &normalize/1)
    |> validate_change(:mapping, fn :mapping, mapping ->
      if Enum.all?(mapping, fn {from, to} -> letter?(from) and letter?(to) end),
        do: [],
        else: [mapping: "use single letters A–Z"]
    end)
  end

  # Upcases, trims and drops empty entries.
  defp normalize(mapping) do
    for {from, to} <- mapping || %{},
        to = to |> to_string() |> String.trim() |> String.upcase(),
        to != "",
        into: %{},
        do: {String.upcase(from), to}
  end

  defp letter?(<<c>>) when c in ?A..?Z, do: true
  defp letter?(_), do: false

  @impl true
  def decode(text, %{mapping: mapping}) do
    Alphabet.map_letters(text, fn i ->
      case Map.get(mapping, <<?A + i>>) do
        <<c>> when c in ?A..?Z -> c - ?A
        _ -> nil
      end
    end)
  end

  @impl true
  def summary(%{mapping: mapping}) do
    used = mapping |> Map.values() |> Enum.frequencies()

    case for {letter, n} <- used, n > 1, do: letter do
      [] -> nil
      dupes -> "Used for several letters: #{dupes |> Enum.sort() |> Enum.join(", ")}"
    end
  end
end
