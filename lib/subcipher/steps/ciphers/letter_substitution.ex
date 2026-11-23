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
    do: "Map each letter to another one by hand, like the symbol substitution cipher."

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
  # The mapping read backwards (plain letter -> cipher letter); plain letters
  # no cipher letter maps to can't be encoded and become "·".
  def encode(text, %{mapping: mapping}) do
    inverse =
      mapping
      |> Enum.sort()
      |> Enum.reverse()
      |> Map.new(fn {<<from>>, <<to>>} -> {to - ?A, from - ?A} end)

    Alphabet.map_letters(text, &Map.get(inverse, &1))
  end

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

  # Starting points for the alphabet grid. Applying one replaces the whole
  # mapping.
  @impl true
  def suggestions(input, _params) do
    present = Alphabet.letters_by_frequency(input)

    if present == [] do
      []
    else
      by_frequency = present |> Enum.zip(Alphabet.english_order()) |> Map.new()

      caesar_shift =
        Enum.min_by(1..25, fn shift ->
          input |> Alphabet.map_letters(&rem(&1 - shift + 26, 26)) |> Alphabet.english_score()
        end)

      [
        {by_frequency, "Frequency match",
         "The most frequent letters mapped to the most frequent English ones (E, T, A, O, I, N…): a starting point, fix the wrong ones by hand."},
        {alphabet_mapping(&rem(&1 - caesar_shift + 26, 26)), "Caesar shift #{caesar_shift}",
         "If the letters were simply shifted, shift #{caesar_shift} gives the most English-like letter frequencies."},
        {alphabet_mapping(&(25 - &1)), "Atbash",
         "The reversed alphabet (A ↔ Z, B ↔ Y…), a common simple substitution."}
      ]
      |> Enum.map(fn {mapping, label, why} ->
        output = decode(input, %{mapping: mapping})
        # Frequency matching gets English letter frequencies by construction:
        # rank by the English words the result contains first.
        score = {-length(Alphabet.common_words(output)), Alphabet.english_score(output)}
        {score, label, mapping, why, output}
      end)
      |> Enum.sort_by(&elem(&1, 0))
      |> Enum.map(fn {_score, label, mapping, why, output} ->
        hint =
          case Alphabet.words_hint(output) do
            nil -> ""
            hint -> " The result " <> hint <> "."
          end

        %{label: label, params: %{mapping: mapping}, reason: why <> hint}
      end)
    end
  end

  # The mapping of every letter through `fun` (on indexes 0..25).
  defp alphabet_mapping(fun), do: Map.new(0..25, &{<<?A + &1>>, <<?A + fun.(&1)>>})

  # The letters of the input as symbols, with word breaks; the letters
  # already mapped by the user are kept.
  @impl true
  def solve(input, %{mapping: current}) do
    tokens =
      input
      |> String.upcase()
      |> String.graphemes()
      |> Enum.map(fn c -> if c =~ ~r/^[A-Z]$/, do: c, else: :gap end)

    fixed = Map.filter(current || %{}, fn {_, to} -> to =~ ~r/^[A-Z]$/ end)

    case Subcipher.Solver.solve(tokens, fixed: fixed) do
      {:ok, %{mapping: solved}} ->
        mapping = Map.merge(solved, fixed)
        kept = if fixed == %{}, do: "", else: " Your #{map_size(fixed)} letter(s) were kept."

        {:ok,
         %{
           label: "Solver",
           params: %{mapping: mapping},
           reason: Subcipher.Solver.explain(decode(input, %{mapping: mapping})) <> kept
         }}

      {:error, :too_short} ->
        {:error, "Too short to solve: at least 8 letters are needed."}
    end
  end
end
