defmodule Subcipher.Steps.Ciphers.KeywordSubstitution do
  @moduledoc """
  Keyword substitution: the cipher alphabet is the keyword (without repeated
  letters) followed by the rest of the alphabet in order. With the keyword
  ZEBRA: A→Z, B→E, C→B, D→R, E→A, F→C, G→D…
  """
  use Subcipher.Steps.Cipher

  @impl true
  def type, do: "keyword_substitution"

  @impl true
  def osrs_usage, do: "Fallen From Grace: the back of the Warning note (keyword FAITH)."

  @impl true
  def name, do: "Keyword substitution"

  @impl true
  def description,
    do:
      "The cipher alphabet starts with a keyword (repeated letters removed), followed by the remaining letters in order."

  @impl true
  def fields do
    [
      %{
        name: :keyword,
        type: :string,
        label: "Keyword",
        default: "",
        help: "Letters only; spaces are ignored."
      }
    ]
  end

  @impl true
  def validate(changeset) do
    validate_format(changeset, :keyword, ~r/^[A-Za-z ]*$/, message: "letters only")
  end

  @doc "The cipher alphabet for `keyword`, as a string of 26 letters."
  def cipher_alphabet(keyword) do
    keyword_letters =
      for <<c <- String.upcase(keyword || "")>>, c in ?A..?Z, uniq: true, do: c

    rest = Enum.to_list(?A..?Z) -- keyword_letters
    List.to_string(keyword_letters ++ rest)
  end

  @impl true
  def decode(text, %{keyword: keyword}) do
    # Plain letter i was written as cipher_alphabet[i]: invert that.
    inverse =
      keyword
      |> cipher_alphabet()
      |> String.to_charlist()
      |> Enum.with_index()
      |> Map.new(fn {c, plain} -> {c - ?A, plain} end)

    Alphabet.map_letters(text, &Map.fetch!(inverse, &1))
  end

  @impl true
  def summary(%{keyword: keyword}) do
    "Plain  ABCDEFGHIJKLMNOPQRSTUVWXYZ\nCipher #{cipher_alphabet(keyword)}"
  end

  # Keywords worth trying: the ones known from Old School RuneScape first,
  # then common choices.
  @known_keywords [
    {"FAITH", "The key of the Warning note in Fallen From Grace (OSRS)."},
    {"ZAROS", "A god of Gielinor, a plausible keyword in OSRS puzzles."},
    {"GUTHIX", "A god of Gielinor, a plausible keyword in OSRS puzzles."},
    {"SARADOMIN", "A god of Gielinor, a plausible keyword in OSRS puzzles."},
    {"ZAMORAK", "A god of Gielinor, a plausible keyword in OSRS puzzles."},
    {"GIELINOR", "The world of RuneScape, a plausible keyword."},
    {"KEYWORD", "A common textbook keyword."},
    {"ZEBRAS", "The usual textbook example of a keyword cipher."},
    {"SECRET", "A common textbook keyword."},
    {"CIPHER", "A common textbook keyword."}
  ]

  # Tries the known keywords and keeps the most English-like results.
  @impl true
  def suggestions(input, _params) do
    if Alphabet.frequencies(input) == %{} do
      []
    else
      @known_keywords
      |> Enum.map(fn {keyword, why} ->
        output = decode(input, %{keyword: keyword})
        {Alphabet.english_score(output), keyword, why, output}
      end)
      |> Enum.sort()
      |> Enum.take(5)
      |> Enum.map(fn {_score, keyword, why, output} ->
        hint =
          case Alphabet.words_hint(output) do
            nil -> ""
            hint -> " The result " <> hint <> "."
          end

        %{label: "Keyword #{keyword}", params: %{keyword: keyword}, reason: why <> hint}
      end)
    end
  end
end
