defmodule Subcipher.Steps.CiphersTest do
  use ExUnit.Case, async: true

  alias Subcipher.Steps
  alias Subcipher.Steps.Alphabet

  alias Subcipher.Steps.Ciphers.{
    Caesar,
    KeywordSubstitution,
    LetterSubstitution,
    SymbolSubstitution
  }

  @sample "Hello, World! ·· 42 é\nnext LINE"

  # Contract every registered cipher must honour; new cipher types are
  # covered automatically.
  describe "every registered cipher" do
    for cipher <- Steps.ciphers() do
      @cipher cipher

      test "#{inspect(cipher)} follows the Cipher contract" do
        assert {:ok, @cipher} = Steps.fetch_cipher(@cipher.type())
        assert is_binary(@cipher.name()) and is_binary(@cipher.description())

        for field <- @cipher.fields() do
          assert field.type in [
                   :integer,
                   :string,
                   :select,
                   :letter_map,
                   :symbol_map,
                   :permutation
                 ]

          assert Map.has_key?(field, :default) and is_binary(field.label)

          if field.type == :select do
            assert field.default in Enum.map(field.options, &elem(&1, 1))
          end
        end

        # Default parameters are valid, and decoding with them keeps the
        # layout: length of the text, spaces and line breaks.
        changeset = Steps.params_changeset(@cipher.type(), %{})
        assert changeset.valid?
        output = @cipher.decode(@sample, Ecto.Changeset.apply_changes(changeset))
        assert String.length(output) == String.length(@sample)
        assert String.replace(output, ~r/\S/u, "") == String.replace(@sample, ~r/\S/u, "")
      end
    end

    test "letter ciphers leave everything but letters untouched" do
      letter_wise = ~w(caesar keyword_substitution letter_substitution vigenere atbash)

      for cipher <- Steps.ciphers(), cipher.type() in letter_wise do
        params = cipher.type() |> Steps.params_changeset(%{}) |> Ecto.Changeset.apply_changes()
        output = cipher.decode(@sample, params)

        assert String.replace(output, ~r/[A-Za-z·]/u, "") ==
                 String.replace(@sample, ~r/[A-Za-z·]/u, "")
      end
    end

    test "types are unique" do
      types = Enum.map(Steps.ciphers(), & &1.type())
      assert types == Enum.uniq(types)
    end
  end

  describe "Caesar" do
    test "shifts letters back, keeping case and other characters" do
      assert Caesar.decode("Wkh txlfn eurzq ira, 42 ·", %{shift: 3}) ==
               "The quick brown fox, 42 ·"

      assert Caesar.decode("ABC xyz", %{shift: 0}) == "ABC xyz"
      assert Caesar.decode("NOP", %{shift: 13}) == "ABC"
    end

    test "suggests the most English-looking shift first" do
      encrypted = Caesar.decode("The quick brown fox jumps over the lazy dog", %{shift: 26 - 7})
      assert [%{params: %{shift: 7}} | _] = Caesar.suggestions(encrypted, %{})
    end

    test "rejects shifts outside 0..25 and empty shifts" do
      refute Steps.params_changeset("caesar", %{"shift" => "26"}).valid?
      refute Steps.params_changeset("caesar", %{"shift" => "-1"}).valid?
      refute Steps.params_changeset("caesar", %{"shift" => ""}).valid?
    end
  end

  describe "Keyword substitution" do
    test "builds the cipher alphabet from the keyword" do
      assert KeywordSubstitution.cipher_alphabet("Zebras") == "ZEBRASCDFGHIJKLMNOPQTUVWXY"
      assert KeywordSubstitution.cipher_alphabet("") == "ABCDEFGHIJKLMNOPQRSTUVWXYZ"
      assert KeywordSubstitution.cipher_alphabet("a b a") == "ABCDEFGHIJKLMNOPQRSTUVWXYZ"
    end

    test "decodes text encrypted with the keyword alphabet" do
      # HELLO with ZEBRAS: H→D, E→A, L→I, O→L
      assert KeywordSubstitution.decode("Daiil, ·!", %{keyword: "zebras"}) == "Hello, ·!"
    end

    test "accepts letters and spaces only" do
      assert Steps.params_changeset("keyword_substitution", %{"keyword" => "Two words"}).valid?
      refute Steps.params_changeset("keyword_substitution", %{"keyword" => "abc1"}).valid?
    end
  end

  describe "Letter substitution" do
    test "maps cipher letters to plain letters, unknown ones to ·" do
      mapping = %{"X" => "T", "Q" => "H", "Z" => "E"}
      assert LetterSubstitution.decode("XQZ xqz AB!", %{mapping: mapping}) == "THE the ··!"
    end

    test "normalizes input and rejects anything but single letters" do
      changeset =
        Steps.params_changeset("letter_substitution", %{
          "mapping" => %{"a" => " t ", "B" => "", "C" => "h"}
        })

      assert changeset.valid?
      assert Ecto.Changeset.get_field(changeset, :mapping) == %{"A" => "T", "C" => "H"}

      refute Steps.params_changeset("letter_substitution", %{"mapping" => %{"A" => "TH"}}).valid?
      refute Steps.params_changeset("letter_substitution", %{"mapping" => %{"A" => "1"}}).valid?
    end

    test "points out plain letters used twice" do
      assert LetterSubstitution.summary(%{mapping: %{"A" => "E", "B" => "E"}}) =~ "E"
      assert LetterSubstitution.summary(%{mapping: %{"A" => "E"}}) == nil
    end
  end

  describe "Symbol substitution" do
    test "substitutes any character, keeping whitespace and unknown marks" do
      mapping = %{"☀" => "T", "[" => "H", "4" => "E"}

      assert SymbolSubstitution.decode("☀[4 ♪·\n☀", %{mapping: mapping}) == "THE ··\nT"
    end

    test "form keys survive characters that can't be parameter names" do
      for symbol <- ["☀", "[", "]", "a", "1", "é"] do
        key = SymbolSubstitution.form_key(symbol)
        assert key =~ ~r/^u[\d-]+$/

        changeset = Steps.params_changeset("symbol_substitution", %{"mapping" => %{key => " x "}})
        assert Ecto.Changeset.get_field(changeset, :mapping) == %{symbol => "X"}
      end
    end

    test "substitutions are at most 3 characters" do
      assert Steps.params_changeset("symbol_substitution", %{"mapping" => %{"☀" => "THE"}}).valid?

      refute Steps.params_changeset("symbol_substitution", %{"mapping" => %{"☀" => "THEN"}}).valid?
    end

    test "symbol_frequencies/1 lists distinct symbols, most frequent first" do
      assert Alphabet.symbol_frequencies("☀[ ☀ · \n♪") == [{"☀", 2}, {"[", 1}, {"♪", 1}]
    end
  end

  test "select fields only accept their options" do
    assert Steps.params_changeset("reverse", %{"mode" => "words"}).valid?
    refute Steps.params_changeset("reverse", %{"mode" => "sideways"}).valid?
    refute Steps.params_changeset("letter_numbers", %{"first" => ""}).valid?
  end

  test "english_score/1 prefers English text" do
    assert Alphabet.english_score("the quick brown fox jumps over the lazy dog") <
             Alphabet.english_score("qeb nrfzh yoltk clu grjmp lsbo qeb ixwv ald")

    assert Alphabet.english_score("· 42 ·") == :infinity
  end
end
