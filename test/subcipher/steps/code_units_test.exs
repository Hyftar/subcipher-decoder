defmodule Subcipher.Steps.CodeUnitsTest do
  use ExUnit.Case, async: true

  alias Subcipher.Guesser
  alias Subcipher.Steps.Ciphers.{Ascii, LetterNumbers, Morse, Unicode}

  defp ascii(base, width \\ "8"), do: %{base: base, width: width}
  defp unicode(base, encoding), do: %{base: base, encoding: encoding}

  describe "ASCII in binary" do
    test "groups of 8 or 7 bits, separated or run together, with prefixes" do
      assert Ascii.decode("01001000 01101001", ascii("2")) == "Hi"
      assert Ascii.decode("0100100001101001", ascii("2")) == "Hi"
      assert Ascii.decode("10010001101001", ascii("2", "7")) == "Hi"
      assert Ascii.decode("0b01001000, 0b01101001", ascii("2")) == "Hi"
    end

    test "encodes back, characters outside ASCII as ?" do
      assert Ascii.encode("Hi", ascii("2")) == "01001000 01101001"
      assert Ascii.encode("Hi", ascii("2", "7")) == "1001000 1101001"
      assert Ascii.encode("é", ascii("2")) == "00111111"
    end

    test "codes above 127, control characters and non-binary lines" do
      assert Ascii.decode("11111111 00000001", ascii("2")) == "··"
      assert Ascii.decode("01001000\nnot binary", ascii("2")) == "H\nnot binary"
    end

    test "suggests 7 bits when they are run together that way" do
      [best | _] = Ascii.suggestions("10010001101001", %{})
      assert best.params == %{base: "2", width: "7"}
    end
  end

  describe "ASCII in hexadecimal" do
    test "pairs, separated or run together, with prefixes" do
      assert Ascii.decode("48 69 21", ascii("16")) == "Hi!"
      assert Ascii.decode("486921", ascii("16")) == "Hi!"
      assert Ascii.decode("0x48 \\x69 &#x21;", ascii("16")) == "Hi!"
      assert Ascii.encode("Hi!", ascii("16")) == "48 69 21"
    end

    test "words of the letters A–F aren't recognized" do
      assert Ascii.recognize("48 69") =~ "hexadecimal"
      assert Ascii.recognize("bead cafe") == nil
    end
  end

  describe "ASCII in decimal" do
    test "numbers, separated, padded and run together, or HTML entities" do
      assert Ascii.decode("72 105 33", ascii("10")) == "Hi!"
      assert Ascii.decode("72,105,33", ascii("10")) == "Hi!"
      assert Ascii.decode("072105033", ascii("10")) == "Hi!"
      assert Ascii.decode("&#72;&#105;&#33;", ascii("10")) == "Hi!"
      assert Ascii.encode("Hi!", ascii("10")) == "72 105 33"
    end

    test "codes above 127 become ·" do
      assert Ascii.decode("72 200", ascii("10")) == "H·"
    end

    test "suggests the base the text decodes in" do
      assert [%{params: %{base: "10"}} | _] = Ascii.suggestions("72 101 108 108 111", %{})
      assert [%{params: %{base: "16"}} | _] = Ascii.suggestions("48 69 21", %{})
      assert [%{params: %{base: "2"}} | _] = Ascii.suggestions("01001000 01101001", %{})
    end

    test "letter numbers aren't ASCII codes" do
      assert Ascii.recognize("8 5 12 12 15") == nil
      assert LetterNumbers.recognize("8 5 12 12 15")
    end
  end

  describe "Unicode" do
    test "UTF-8 bytes and code points, in every base" do
      assert Unicode.decode("11100010 10011000 10000000", unicode("2", "utf8")) == "☀"
      assert Unicode.decode("10011000000000", unicode("2", "code_points")) == "☀"
      assert Unicode.decode("E2 98 80", unicode("16", "utf8")) == "☀"
      assert Unicode.decode("E29880", unicode("16", "utf8")) == "☀"
      assert Unicode.decode("U+2600 U+0048", unicode("16", "code_points")) == "☀H"
      assert Unicode.decode("\\u2600\\u0048", unicode("16", "code_points")) == "☀H"
      assert Unicode.decode("226 152 128", unicode("10", "utf8")) == "☀"
      assert Unicode.decode("9728 72", unicode("10", "code_points")) == "☀H"
      assert Unicode.decode("&#9728;&#72;", unicode("10", "code_points")) == "☀H"
    end

    test "encodes code points as U+ in hexadecimal" do
      assert Unicode.encode("☀H", unicode("16", "code_points")) == "U+2600 U+0048"
      assert Unicode.encode("☀H", unicode("10", "code_points")) == "9728 72"
      assert Unicode.encode("☀", unicode("10", "utf8")) == "226 152 128"
    end

    test "hexadecimal words and plain numbers aren't code points without a prefix" do
      assert Unicode.recognize("bead cafe") == nil
      assert Unicode.recognize("aaa bbb aaa") == nil
      assert Unicode.recognize("U+0AAA U+0BBB") =~ "code points"
    end

    test "invalid UTF-8 and code points become ·" do
      assert Unicode.decode("E2 98", unicode("16", "utf8")) == "·"
      assert Unicode.decode("D800 110000", unicode("16", "code_points")) == "··"
    end

    test "round trips" do
      for base <- ~w(10 16 2), encoding <- ~w(utf8 code_points), text <- ["Hello ☀ é", "日本"] do
        params = unicode(base, encoding)
        assert Unicode.decode(Unicode.encode(text, params), params) == text
      end
    end

    test "suggests the reading that decodes everything; U+ means code points" do
      assert [%{params: %{base: "2", encoding: "code_points"}} | _] =
               Unicode.suggestions("10011000000000", %{})

      assert [%{params: %{base: "16", encoding: "code_points"}} | _] =
               Unicode.suggestions("U+0048 U+0069", %{})

      assert [%{params: %{base: "16", encoding: "utf8"}} | _] =
               Unicode.suggestions("E2 98 80", %{})

      assert [%{params: %{base: "10", encoding: "code_points"}} | _] =
               Unicode.suggestions("9728 72", %{})
    end
  end

  describe "guessing" do
    defp winner(text) do
      {:ok, %{guesses: [best | _]}} = Guesser.guess(text)
      best
    end

    test "each format is recognized and wins" do
      for {text, cipher, output} <- [
            {"01001000 01101001", Ascii, "Hi"},
            {"48 65 6C 6C 6F", Ascii, "Hello"},
            {"72 101 108 108 111", Ascii, "Hello"},
            {"11100010 10011000 10000000 00100000 01001000", Unicode, "☀ H"},
            {"U+2600 U+0048 U+0069", Unicode, "☀Hi"},
            {"9728 32 72 105", Unicode, "☀ Hi"}
          ] do
        best = winner(text)
        assert {best.cipher, best.output} == {cipher, output}
        assert best.recognized
      end
    end

    test "Morse steps aside for bytes, but keeps 0s and 1s that aren't" do
      assert Morse.recognize("01001000 01101001") == nil
      assert winner("000 111 000").cipher == Morse
    end
  end
end
