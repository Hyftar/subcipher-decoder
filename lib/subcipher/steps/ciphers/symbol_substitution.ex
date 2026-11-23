defmodule Subcipher.Steps.Ciphers.SymbolSubstitution do
  @moduledoc """
  Symbol substitution on text: every distinct character of the input (except
  whitespace) is a symbol, substituted by hand with a letter, like the
  symbols of pictures. Unknown symbols are shown as "·".
  """
  use Subcipher.Steps.Cipher

  @impl true
  def type, do: "symbol_substitution"

  @impl true
  def osrs_usage,
    do:
      "Symbol alphabets: The Writing's on the Wall symbols, the Lunar alphabet, the VPSG code (What Lies Below), Secrets of the North's strange cipher. Start from pictures to detect the symbols."

  @impl true
  def name, do: "Symbol substitution"

  @impl true
  def description,
    do: "Every distinct character is a symbol: replace each one by the letter it stands for."

  @impl true
  def fields do
    [%{name: :mapping, type: :symbol_map, label: "Symbol → letter", default: %{}}]
  end

  @impl true
  def validate(changeset) do
    changeset
    |> update_change(:mapping, &normalize/1)
    |> validate_change(:mapping, fn :mapping, mapping ->
      if Enum.all?(mapping, fn {_symbol, to} -> String.length(to) <= 3 end),
        do: [],
        else: [mapping: "a substitution is at most 3 characters"]
    end)
  end

  @doc """
  Key of a symbol in form parameters: its codepoints ("u9728" for "☀"), as
  characters like "[" or "]" can't be used in parameter names.
  """
  def form_key(symbol), do: "u" <> Enum.map_join(String.to_charlist(symbol), "-", &to_string/1)

  defp decode_key("u" <> codes = key) do
    if codes =~ ~r/^\d+(-\d+)*$/,
      do: codes |> String.split("-") |> Enum.map(&String.to_integer/1) |> List.to_string(),
      else: key
  end

  defp decode_key(key), do: key

  # Decodes form keys, upcases and trims letters, drops empty entries.
  defp normalize(mapping) do
    for {symbol, to} <- mapping || %{},
        to = to |> to_string() |> String.trim() |> String.upcase(),
        to != "",
        into: %{},
        do: {decode_key(symbol), to}
  end

  @impl true
  def decode(text, %{mapping: mapping}) do
    text
    |> String.graphemes()
    |> Enum.map_join(fn char ->
      cond do
        char =~ ~r/^\s$/u -> char
        char == Alphabet.unknown() -> char
        true -> Map.get(mapping, char, Alphabet.unknown())
      end
    end)
  end

  @impl true
  def summary(%{mapping: mapping}) do
    used = mapping |> Map.values() |> Enum.frequencies()

    case for {letter, n} <- used, n > 1, do: letter do
      [] -> nil
      dupes -> "Used for several symbols: #{dupes |> Enum.sort() |> Enum.join(", ")}"
    end
  end
end
