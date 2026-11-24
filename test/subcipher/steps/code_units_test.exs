defmodule Subcipher.Steps.CodeUnitsTest do
  use ExUnit.Case, async: true

  alias Subcipher.Guesser
  alias Subcipher.Steps.Ciphers.{BinaryAscii, BinaryUnicode, HexAscii, HexUnicode, Morse}

  describe "binary ASCII" do
    test "groups of 8 or 7 bits, separated or run together, with prefixes" do
      assert BinaryAscii.decode("01001000 01101001", %{width: "8"}) == "Hi"
      assert BinaryAscii.decode("0100100001101001", %{width: "8"}) == "Hi"
      assert BinaryAscii.decode("10010001101001", %{width: "7"}) == "Hi"
      assert BinaryAscii.decode("0b01001000, 0b01101001", %{width: "8"}) == "Hi"
    end

    test "encodes back, characters outside ASCII as ?" do
      assert BinaryAscii.encode("Hi", %{width: "8"}) == "01001000 01101001"
      assert BinaryAscii.encode("é", %{width: "8"}) == "00111111"
    end

    test "codes above 127, control characters and non-binary lines" do
      assert BinaryAscii.decode("11111111 00000001", %{width: "8"}) == "··"
      assert BinaryAscii.decode("01001000\nnot binary", %{width: "8"}) == "H\nnot binary"
    end

    test "suggests 7 bits when they are run together that way" do
      [best | _] = BinaryAscii.suggestions("10010001101001", %{})
      assert best.params == %{width: "7"}
    end
  end

  describe "hexadecimal ASCII" do
    test "pairs, separated or run together, with prefixes" do
      assert HexAscii.decode("48 69 21", %{}) == "Hi!"
      assert HexAscii.decode("486921", %{}) == "Hi!"
      assert HexAscii.decode("0x48 \\x69 &#x21;", %{}) == "Hi!"
      assert HexAscii.encode("Hi!", %{}) == "48 69 21"
    end

    test "words of the letters A–F aren't recognized" do
      assert HexAscii.recognize("48 69") =~ "ASCII"
      assert HexAscii.recognize("bead cafe") == nil
    end
  end

  describe "Unicode" do
    test "UTF-8 bytes and code points, in binary and hexadecimal" do
      assert BinaryUnicode.decode("11100010 10011000 10000000", %{encoding: "utf8"}) == "☀"
      assert BinaryUnicode.decode("10011000000000", %{encoding: "code_points"}) == "☀"
      assert HexUnicode.decode("E2 98 80", %{encoding: "utf8"}) == "☀"
      assert HexUnicode.decode("E29880", %{encoding: "utf8"}) == "☀"
      assert HexUnicode.decode("U+2600 U+0048", %{encoding: "code_points"}) == "☀H"
      assert HexUnicode.decode("\\u2600\\u0048", %{encoding: "code_points"}) == "☀H"
    end

    test "invalid UTF-8 and code points become ·" do
      assert HexUnicode.decode("E2 98", %{encoding: "utf8"}) == "·"
      assert HexUnicode.decode("D800 110000", %{encoding: "code_points"}) == "··"
    end

    test "round trips" do
      for encoding <- ~w(utf8 code_points), text <- ["Hello ☀ é", "日本"] do
        params = %{encoding: encoding}
        assert BinaryUnicode.decode(BinaryUnicode.encode(text, params), params) == text
        assert HexUnicode.decode(HexUnicode.encode(text, params), params) == text
      end
    end

    test "suggests the encoding that decodes everything; U+ means code points" do
      assert [%{params: %{encoding: "code_points"}} | _] =
               BinaryUnicode.suggestions("10011000000000", %{})

      assert [%{params: %{encoding: "code_points"}} | _] =
               HexUnicode.suggestions("U+0048 U+0069", %{})

      assert [%{params: %{encoding: "utf8"}} | _] = HexUnicode.suggestions("E2 98 80", %{})
    end
  end

  describe "guessing" do
    defp winner(text) do
      {:ok, %{guesses: [best | _]}} = Guesser.guess(text)
      best
    end

    test "each format is recognized and wins" do
      for {text, cipher, output} <- [
            {"01001000 01101001", BinaryAscii, "Hi"},
            {"48 65 6C 6C 6F", HexAscii, "Hello"},
            {"11100010 10011000 10000000 00100000 01001000", BinaryUnicode, "☀ H"},
            {"U+2600 U+0048 U+0069", HexUnicode, "☀Hi"}
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
