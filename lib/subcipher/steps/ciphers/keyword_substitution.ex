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
end
