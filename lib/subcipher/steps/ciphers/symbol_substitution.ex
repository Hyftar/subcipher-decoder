defmodule Subcipher.Steps.Ciphers.SymbolSubstitution do
  @moduledoc """
  Symbol substitution on text: every distinct character of the input (except
  whitespace) is a symbol, substituted by hand with a letter, like the
  symbols of pictures. Unknown symbols are shown as "·".
  """
  use Subcipher.Steps.Cipher

  @impl true
  def type, do: "symbol_substitution"

  # Mostly from pictures (symbols are detected), or typed symbols like ☀♪Θ.
  @impl true
  def input_kinds, do: [:pictures, :text]

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
  # The mapping read backwards (letters -> symbol), longest substitutions
  # first ("TH" before "T"). Letters no symbol stands for become "·";
  # anything else is kept.
  def encode(text, %{mapping: mapping}) do
    inverse =
      mapping
      |> Enum.sort()
      |> Enum.reverse()
      |> Map.new(fn {symbol, letters} -> {String.upcase(letters), symbol} end)

    lengths =
      inverse |> Map.keys() |> Enum.map(&String.length/1) |> Enum.uniq() |> Enum.sort(:desc)

    encode_symbols(String.upcase(text), inverse, lengths, [])
  end

  defp encode_symbols("", _inverse, _lengths, acc), do: acc |> Enum.reverse() |> Enum.join()

  defp encode_symbols(text, inverse, lengths, acc) do
    case Enum.find_value(lengths, &match_symbol(text, inverse, &1)) do
      {symbol, rest} ->
        encode_symbols(rest, inverse, lengths, [symbol | acc])

      nil ->
        {char, rest} = String.split_at(text, 1)
        out = if char =~ ~r/^[A-Z]$/, do: Alphabet.unknown(), else: char
        encode_symbols(rest, inverse, lengths, [out | acc])
    end
  end

  defp match_symbol(text, inverse, length) do
    {head, rest} = String.split_at(text, length)

    case inverse do
      %{^head => symbol} -> {symbol, rest}
      _ -> nil
    end
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

  # Starting points for the symbol grid. Applying one replaces the whole
  # mapping.
  @impl true
  def suggestions(input, _params) do
    symbols = input |> Alphabet.symbol_frequencies() |> Enum.map(&elem(&1, 0))

    if symbols == [] do
      []
    else
      by_frequency = symbols |> Enum.zip(Alphabet.english_order()) |> Map.new()

      frequency = %{
        label: "Frequency match",
        params: %{mapping: by_frequency},
        reason:
          "The most frequent symbols mapped to the most frequent English letters (E, T, A, O, I, N…): a starting point, fix the wrong ones by hand." <>
            if(length(symbols) > 26,
              do: " There are #{length(symbols)} symbols, more than letters: some stay unknown.",
              else: ""
            )
      }

      # Symbols that are letters already (e.g. after another step).
      letters = Enum.filter(symbols, &(&1 =~ ~r/^[A-Za-z]$/))

      as_is =
        if letters != [] do
          [
            %{
              label: "Letters as they are",
              params: %{mapping: Map.new(letters, &{&1, String.upcase(&1)})},
              reason:
                "#{length(letters)} of the #{length(symbols)} symbols are letters already: keep them, then substitute the rest."
            }
          ]
        else
          []
        end

      [frequency | as_is]
    end
  end

  # Each distinct character is a symbol; whitespace separates words; the
  # symbols already given a single letter by the user are kept.
  @impl true
  def solve(input, %{mapping: current}) do
    tokens =
      input
      |> String.graphemes()
      |> Enum.map(fn c -> if c =~ ~r/^\s$/u or c == Alphabet.unknown(), do: :gap, else: c end)

    fixed = Map.filter(current || %{}, fn {_, to} -> to =~ ~r/^[A-Z]$/ end)

    case Subcipher.Solver.solve(tokens, fixed: fixed) do
      {:ok, %{mapping: solved}} ->
        mapping = Map.merge(current || %{}, solved)
        kept = if fixed == %{}, do: "", else: " Your #{map_size(fixed)} letter(s) were kept."

        {:ok,
         %{
           label: "Solver",
           params: %{mapping: mapping},
           reason: Subcipher.Solver.explain(decode(input, %{mapping: mapping})) <> kept
         }}

      {:error, :too_short} ->
        {:error, "Too short to solve: at least 8 symbols are needed."}
    end
  end
end
