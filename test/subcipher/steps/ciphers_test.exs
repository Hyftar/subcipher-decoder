defmodule Subcipher.Steps.CiphersTest do
  use ExUnit.Case, async: true

  alias Subcipher.Steps
  alias Subcipher.Steps.Alphabet

  alias Subcipher.Steps.Ciphers.{
    Caesar,
    KeywordSubstitution,
    MixedAlphabet,
    Route,
    SymbolSubstitution
  }

  @sample "Hello, World! ·· 42 é\nnext LINE"

  # Ciphers that write the text in a grid: spaces and line breaks are not
  # kept (the characters are).
  @grid_transpositions ~w(route)

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
        # layout: length of the text, spaces and line breaks (transpositions
        # that write the text in a grid keep its characters, not the layout).
        changeset = Steps.params_changeset(@cipher.type(), %{})
        assert changeset.valid?
        output = @cipher.decode(@sample, Ecto.Changeset.apply_changes(changeset))

        if @cipher.type() in @grid_transpositions do
          assert Enum.sort(String.graphemes(output)) ==
                   Enum.sort(String.graphemes(String.replace(@sample, ~r/\s/u, "")))
        else
          assert String.length(output) == String.length(@sample)
          assert String.replace(output, ~r/\S/u, "") == String.replace(@sample, ~r/\S/u, "")
        end
      end
    end

    test "letter ciphers leave everything but letters untouched" do
      letter_wise = ~w(caesar keyword_substitution mixed_alphabet vigenere atbash)

      for cipher <- Steps.ciphers(), cipher.type() in letter_wise do
        params = cipher.type() |> Steps.params_changeset(%{}) |> Ecto.Changeset.apply_changes()
        output = cipher.decode(@sample, params)

        assert String.replace(output, ~r/[A-Za-z·]/u, "") ==
                 String.replace(@sample, ~r/[A-Za-z·]/u, "")
      end
    end

    # Settings for the round trip of each cipher that can encode.
    @round_trip_params %{
      "caesar" => %{"shift" => 11},
      "keyword_substitution" => %{"keyword" => "Zebras"},
      "vigenere" => %{"key" => "LEMON"},
      "atbash" => %{},
      "reverse" => %{"mode" => "words"},
      "morse" => %{},
      "letter_numbers" => %{"first" => "0"},
      "route" => %{"width" => 4, "route" => "spiral_clockwise", "corner" => "bottom_left"},
      "mixed_alphabet" => %{
        "mapping" => Map.new(?A..?Z, &{<<&1>>, <<?A + rem(&1 - ?A + 5, 26)>>})
      },
      "symbol_substitution" => %{
        "mapping" =>
          Map.new(
            Enum.zip(
              ~w(☀ ♪ Θ ♠ Φ ☎ ★ ♣ ♥ ♦ ☂ ✈ ⚓ ☯ ⚑ ✿ ☘ ⌘ Ω Δ Ψ Σ Λ Ξ Π Γ),
              Enum.map(?A..?Z, &<<&1>>)
            )
          )
      }
    }

    test "every cipher that can encode round-trips: decode(encode(text)) == text" do
      text = "Hello World\nthe second line"

      for cipher <- Steps.ciphers(), Steps.implements?(cipher, :encode, 2) do
        assert Map.has_key?(@round_trip_params, cipher.type()),
               "add round-trip settings for #{cipher.type()}"

        params =
          cipher.type()
          |> Steps.params_changeset(@round_trip_params[cipher.type()])
          |> Ecto.Changeset.apply_changes()

        encoded = cipher.encode(text, params)

        refute encoded == text and cipher.type() not in ~w(reverse),
               "#{cipher.type()} didn't encode"

        expected =
          if cipher.type() in @grid_transpositions,
            do: String.replace(text, ~r/\s/u, ""),
            else: text

        assert String.upcase(cipher.decode(encoded, params)) == String.upcase(expected),
               cipher.type()
      end
    end

    test "an anagram's order only fits its own text: no encode" do
      {:ok, anagram} = Steps.fetch_cipher("anagram")
      refute Steps.implements?(anagram, :encode, 2)
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

  describe "Route cipher" do
    # The examples of https://crypto.interactive-maths.com/route-cipher.html
    @plain "abort the mission, you have been spotted"

    defp route_params(width, route, corner),
      do: %{width: width, route: route, corner: corner, null: "X"}

    test "encodes the page's examples: down the columns, spiral from the bottom right" do
      assert String.upcase(Route.encode(@plain, route_params(5, "columns", "top_left"))) ==
               "ATSYV NTBHS OESEO EIUBP DRMOH EOXTI NAETX"

      assert String.upcase(
               Route.encode(@plain, route_params(5, "spiral_anticlockwise", "bottom_right"))
             ) == "XTEAN ITROB ATSYV NTEDX OEHOM EHSOE SPBUI"
    end

    test "decodes the page's example, dropping the null" do
      assert Route.decode(
               "RAEWE CREDX ESIDO V",
               route_params(4, "spiral_anticlockwise", "top_right")
             ) ==
               "WEAREDISCOVERED"
    end

    test "routes from each corner; an incomplete last row is skipped" do
      assert Route.route(6, 3, "zigzag", "bottom_right") ==
               [{1, 2}, {0, 2}, {0, 1}, {1, 1}, {1, 0}, {0, 0}]

      assert Route.route(9, 3, "spiral_clockwise", "top_left") ==
               [{0, 0}, {0, 1}, {0, 2}, {1, 2}, {2, 2}, {2, 1}, {2, 0}, {1, 0}, {1, 1}]

      assert Route.route(7, 3, "spiral_clockwise", "top_left") ==
               [{0, 0}, {0, 1}, {0, 2}, {1, 2}, {2, 0}, {1, 0}, {1, 1}]

      # A null letter that isn't padding (beyond the last row) is kept.
      assert Route.decode("XXXX", route_params(2, "columns", "top_left")) == "XXX"
    end

    test "suggestions find the width, route and corner" do
      plain = "the treasure is buried under the old oak tree near the river bend at midnight"
      params = route_params(6, "spiral_clockwise", "bottom_left")
      encoded = Route.encode(plain, params)

      assert [best | _] = Route.suggestions(encoded, %{})
      assert best.params == Map.delete(params, :null)
      assert best.reason =~ "most English-like"

      assert Route.decode(encoded, Map.put(best.params, :null, "X")) ==
               String.replace(plain, " ", "")
    end
  end

  describe "Mixed alphabet" do
    test "maps cipher letters to plain letters, unknown ones to ·" do
      mapping = %{"X" => "T", "Q" => "H", "Z" => "E"}
      assert MixedAlphabet.decode("XQZ xqz AB!", %{mapping: mapping}) == "THE the ··!"
    end

    test "normalizes input and rejects anything but single letters" do
      changeset =
        Steps.params_changeset("mixed_alphabet", %{
          "mapping" => %{"a" => " t ", "B" => "", "C" => "h"}
        })

      assert changeset.valid?
      assert Ecto.Changeset.get_field(changeset, :mapping) == %{"A" => "T", "C" => "H"}

      refute Steps.params_changeset("mixed_alphabet", %{"mapping" => %{"A" => "TH"}}).valid?
      refute Steps.params_changeset("mixed_alphabet", %{"mapping" => %{"A" => "1"}}).valid?
    end

    test "points out plain letters used twice" do
      assert MixedAlphabet.summary(%{mapping: %{"A" => "E", "B" => "E"}}) =~ "E"
      assert MixedAlphabet.summary(%{mapping: %{"A" => "E"}}) == nil
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
