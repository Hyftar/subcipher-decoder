defmodule Subcipher.Steps.MorseTest do
  use ExUnit.Case, async: true

  alias Subcipher.Steps
  alias Subcipher.Steps.Ciphers.Morse

  describe "custom symbols" do
    test "decode any two symbols as dots and dashes" do
      assert Morse.decode("000 111 000", %{dot: "0", dash: "1"}) == "SOS"
      assert Morse.decode("aaa bbb aaa / bbb", %{dot: "a", dash: "b"}) == "SOS O"
      # Swapped usual symbols.
      assert Morse.decode("--- ... ---", %{dot: "-", dash: "."}) == "SOS"
    end

    test "encode back with them" do
      params = %{dot: "x", dash: "y"}
      assert Morse.encode("sos", params) == "xxx yyy xxx"
      assert Morse.decode(Morse.encode("Hello world", params), params) == "HELLO WORLD"
    end

    test "the usual symbols by default" do
      assert Morse.decode("... --- ...", %{dot: "", dash: ""}) == "SOS"
      assert Morse.decode("... --- ...", %{}) == "SOS"
    end

    test "dot and dash must be single, different characters" do
      refute Steps.params_changeset("morse", %{"dot" => "ab"}).valid?
      refute Steps.params_changeset("morse", %{"dot" => "a", "dash" => "a"}).valid?
      assert Steps.params_changeset("morse", %{"dot" => "a", "dash" => "b"}).valid?
    end
  end

  describe "suggestions" do
    test "read two symbols both ways, the one giving valid codes first" do
      # With 1 as the dot, "1111" is H; with 0 as the dot, "0000" isn't in the text.
      [best, other] = Morse.suggestions("1111 1 1011 1011 000", %{})

      assert best.params == %{dot: "1", dash: "0", letters: "spaced"}
      assert Morse.decode("1111 1 1011 1011 000", best.params) == "HELLO"
      assert best.reason =~ "only two symbols"
      assert other.params == %{dot: "0", dash: "1", letters: "spaced"}
    end

    test "the usual reading keeps the default symbols" do
      [best | _] = Morse.suggestions("... --- ...", %{})
      assert best.params == %{dot: "", dash: "", letters: "spaced"}
      assert best.label == "Dots and dashes"

      # Too short for the 4-letter sequences of the swapped reading to count.
      [best | _] = Morse.suggestions("... --- ... / ...", %{})
      assert best.params == %{dot: "", dash: "", letters: "spaced"}
    end

    test "a long text read with swapped dots and dashes" do
      text = Morse.encode("meet me at the old mill at midnight", %{dot: "-", dash: "."})
      [best | _] = Morse.suggestions(text, %{})
      assert best.params == %{dot: "-", dash: ".", letters: "spaced"}
    end

    test "nothing for texts of more than two symbols" do
      assert Morse.suggestions("hello world", %{}) == []
    end
  end

  describe "letters run together" do
    @joined %{letters: "joined"}

    test "guesses where letters start, words separated" do
      text = Morse.encode("hello world", @joined)
      assert text == "......-...-..--- / .-----.-..-..-.."
      assert Morse.decode(text, @joined) == "HELLO WORLD"
    end

    test "guesses word breaks too in a long line without any" do
      text = "......-...-..---.-----.-..-..-.."
      assert Morse.decode(text, @joined) == "HELLO WORLD"
    end

    test "short runs stay one word" do
      assert Morse.decode("...---...", @joined) == "SOS"
    end

    test "works with any two symbols" do
      params = %{dot: "0", dash: "1", letters: "joined"}
      assert Morse.decode(Morse.encode("hello world", params), params) == "HELLO WORLD"
    end

    test "suggested when spaced letters give no valid code" do
      [best | _] = Morse.suggestions("-.--.--...--.-", %{})
      assert best.params.letters == "joined"
      assert best.label =~ "run together"
      assert best.reason =~ "without spaces between letters"

      # Valid codes once spaced: not run together.
      [best | _] = Morse.suggestions("... --- ...", %{})
      assert best.params.letters == "spaced"
    end

    test "recognized" do
      assert Morse.recognize("-.--.--...--.-") =~ "run together"
      assert Morse.recognize("abbaabbbaabab") =~ "“b” and “a”"
    end
  end

  describe "recognize" do
    test "two symbols whose groups are all valid codes" do
      assert Morse.recognize("... --- ...") =~ "dots and dashes"
      assert Morse.recognize("000 111 000") =~ "“0” and “1”"
    end

    test "not other texts" do
      assert Morse.recognize("hello world") == nil
      # Three symbols.
      assert Morse.recognize(".- -.. ab") == nil
    end
  end
end
