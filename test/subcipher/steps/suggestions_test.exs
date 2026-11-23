defmodule Subcipher.Steps.SuggestionsTest do
  use ExUnit.Case, async: true

  alias Subcipher.Steps
  alias Subcipher.Steps.Ciphers.{Caesar, KeywordSubstitution, Vigenere}

  @english "It was the best of times, it was the worst of times, it was the age of wisdom, " <>
             "it was the age of foolishness, it was the epoch of belief, it was the epoch of " <>
             "incredulity, it was the season of light, it was the season of darkness"

  # Encrypts by shifting letters forward with a repeating key.
  defp vigenere_encrypt(text, key) do
    shifts = key |> String.upcase() |> String.to_charlist() |> Enum.map(&(&1 - ?A))

    {chars, _} =
      text
      |> String.graphemes()
      |> Enum.map_reduce(0, fn char, i ->
        if char =~ ~r/^[A-Za-z]$/ do
          shift = Enum.at(shifts, rem(i, length(shifts)))
          {Steps.Alphabet.map_letters(char, &rem(&1 + shift, 26)), i + 1}
        else
          {char, i}
        end
      end)

    Enum.join(chars)
  end

  defp defaults(cipher) do
    cipher.type() |> Steps.params_changeset(%{}) |> Ecto.Changeset.apply_changes()
  end

  describe "every cipher that suggests" do
    for cipher <- Steps.ciphers() do
      @cipher cipher

      test "#{inspect(cipher)}: suggestions are explained and valid" do
        input = Caesar.decode(@english, %{shift: 23})
        suggestions = Steps.suggestions(@cipher, input, defaults(@cipher))

        if Steps.implements?(@cipher, :suggestions, 2) do
          assert is_list(suggestions) and length(suggestions) <= 5
          field_names = Enum.map(@cipher.fields(), & &1.name)

          for s <- suggestions do
            assert is_binary(s.label) and s.label != ""
            assert is_binary(s.reason) and String.length(s.reason) > 10
            assert is_binary(s.preview) and is_boolean(s.applied)
            # Only the cipher's own parameters, and valid ones.
            assert s.params |> Map.keys() |> Enum.all?(&(&1 in field_names))

            params = Map.new(s.params, fn {k, v} -> {to_string(k), v} end)
            assert Steps.params_changeset(@cipher.type(), params).valid?
          end
        else
          assert suggestions == nil
        end
      end
    end
  end

  test "ciphers without anything to choose don't suggest" do
    for type <- ~w(atbash morse anagram) do
      {:ok, cipher} = Steps.fetch_cipher(type)
      refute Steps.implements?(cipher, :suggestions, 2)
    end
  end

  test "Caesar: the most English-like shifts, with why" do
    input = Caesar.decode(@english, %{shift: 26 - 7})
    [best | _] = suggestions = Steps.suggestions(Caesar, input, %{shift: 0})

    assert length(suggestions) == 5
    assert best.params == %{shift: 7}
    assert best.preview =~ "It was the best of times"
    assert best.reason =~ "closest to English"
    assert best.reason =~ "THE"
    refute best.applied

    # Once applied, it is marked as such.
    assert [%{applied: true} | _] = Steps.suggestions(Caesar, input, %{shift: 7})
  end

  test "Vigenère: finds the key length, then each key letter" do
    input = vigenere_encrypt(@english, "LEMON")
    [best | _] = Steps.suggestions(Vigenere, input, %{key: ""})

    assert best.params == %{key: "LEMON"}
    assert best.reason =~ "Key length 5"
    assert best.reason =~ "index of coincidence"
    assert best.preview =~ "It was the best of times"

    # Too short to analyse: nothing rather than noise.
    assert Steps.suggestions(Vigenere, "MOYQWVL", %{key: ""}) == []
  end

  test "Keyword substitution: tries known keywords, FAITH from Fallen From Grace" do
    note = "RSFQSEMC WESD RUMQERH, SDQNUCD SN RUMRHS, FMT FR SDH LNNM DFMCR KNW"
    [best | _] = Steps.suggestions(KeywordSubstitution, note, %{keyword: ""})

    assert best.params == %{keyword: "FAITH"}
    assert best.reason =~ "Fallen From Grace"
    assert best.preview =~ "STARTING WITH SUNRISE"
  end

  test "Letter numbers: A = 0 or 1 from the numbers present" do
    {:ok, numbers} = Steps.fetch_cipher("letter_numbers")
    params = %{first: "1"}

    assert [%{params: %{first: "1"}} = one, _] = Steps.suggestions(numbers, "8 1 26", params)
    assert one.reason =~ "26"

    assert [%{params: %{first: "0"}} = zero, _] = Steps.suggestions(numbers, "7 0 25", params)
    assert zero.reason =~ "0"

    assert Steps.suggestions(numbers, "no numbers", params) == []
  end

  test "Reversed text: modes compared by the English words they give" do
    {:ok, reverse} = Steps.fetch_cipher("reverse")
    suggestions = Steps.suggestions(reverse, "eht kciuq nworb xof", %{mode: "lines"})

    assert hd(suggestions).reason =~ "THE"
    # On one line, reversing it or each word gives the same words: both are
    # offered.
    previews = Enum.map(suggestions, & &1.preview)
    assert "the quick brown fox" in previews
    assert "fox brown quick the" in previews
  end

  test "Letter substitution: frequency match, Caesar- and Atbash-shaped alphabets" do
    {:ok, letters} = Steps.fetch_cipher("letter_substitution")
    input = Caesar.decode(@english, %{shift: 26 - 4})
    suggestions = Steps.suggestions(letters, input, %{mapping: %{}})

    assert Enum.map(suggestions, & &1.label) |> Enum.sort() ==
             ["Atbash", "Caesar shift 4", "Frequency match"]

    # A Caesar-encrypted text: that alphabet decodes it best.
    assert %{label: "Caesar shift 4", preview: "It was the best" <> _} = hd(suggestions)
  end

  test "Symbol substitution: most frequent symbols to the most frequent letters" do
    {:ok, symbols} = Steps.fetch_cipher("symbol_substitution")
    [frequency] = Steps.suggestions(symbols, "☀♪Θ ☀♪ ☀", %{mapping: %{}})

    assert frequency.params == %{mapping: %{"☀" => "E", "♪" => "T", "Θ" => "A"}}
    assert frequency.preview == "ETA ET E"

    # Letters already there can be kept.
    assert [_, %{label: "Letters as they are"}] =
             Steps.suggestions(symbols, "☀b a", %{mapping: %{}})
  end
end
