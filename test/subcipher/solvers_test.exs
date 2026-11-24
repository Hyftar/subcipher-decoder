defmodule Subcipher.SolversTest do
  use ExUnit.Case, async: true

  alias Subcipher.{KeySpace, Steps}
  alias Subcipher.Solvers.KeywordSearch
  alias Subcipher.Steps.Ciphers.{KeywordSubstitution, MixedAlphabet, SymbolSubstitution, Vigenere}

  @plain "Meet me at the old mill at midnight and bring the map with you"
  @long "In the beginning there was nothing but darkness and the gods fought over " <>
          "the world until Guthix put them to sleep and shaped the land"

  describe "key spaces" do
    test "bigger key spaces cost more" do
      assert KeySpace.choices(26) < KeySpace.word("DRAGON")
      assert KeySpace.word("DRAGON") < KeySpace.word("QZXRTP")
      assert_in_delta KeySpace.permutation(26), 26.6, 0.1
      assert KeySpace.permutation(5) < KeySpace.permutation(20)
    end
  end

  describe "keyword substitution solver" do
    test "finds dictionary keywords, even on short texts" do
      text =
        KeywordSubstitution.encode("Dig near the fountain in the market square", %{
          keyword: "DRAGON"
        })

      assert {:ok, %{params: %{keyword: "DRAGON"}}} =
               Steps.solve(KeywordSubstitution, text, %{keyword: ""})
    end

    test "finds keywords that aren't words" do
      text = KeywordSubstitution.encode(@long, %{keyword: "VARROCK"})
      {:ok, solution} = KeywordSubstitution.solve(text, %{keyword: ""})
      assert KeywordSubstitution.decode(text, solution.params) =~ "Guthix put them to sleep"
    end

    test "reads the keyword off a solved alphabet" do
      mapping =
        "DRAGONBCEFHIJKLMPQSTUVWXYZ"
        |> String.graphemes()
        |> Enum.zip(Enum.map(?A..?Z, &<<&1>>))
        |> Map.new()

      assert KeywordSearch.keyword_from_mapping(mapping) == ~c"DRAGON" |> Enum.map(&(&1 - ?A))
    end

    test "needs a few letters" do
      assert {:error, _} = KeywordSubstitution.solve("ab cd", %{keyword: ""})
    end
  end

  describe "Vigenère solver" do
    test "finds dictionary keys on short texts" do
      text = Vigenere.encode(@plain, %{key: "WIZARD"})
      {:ok, solution} = Vigenere.solve(text, %{key: ""})
      assert Vigenere.decode(text, solution.params) == @plain
    end

    test "finds free keys on longer texts" do
      text = Vigenere.encode(@long, %{key: "QZKT"})
      {:ok, solution} = Vigenere.solve(text, %{key: ""})
      assert solution.params.key == "QZKT"
    end
  end

  describe "mixed alphabet solver" do
    @short "Dig near the fountain in the market square"

    defp keyword_mapping(keyword) do
      keyword
      |> KeywordSubstitution.cipher_alphabet()
      |> String.graphemes()
      |> Enum.zip(Enum.map(?A..?Z, &<<&1>>))
      |> Map.new()
    end

    test "finds keyword alphabets on texts too short for the general solver" do
      text = MixedAlphabet.encode(@short, %{mapping: keyword_mapping("DRAGON")})
      {:ok, solution} = MixedAlphabet.solve(text, %{mapping: %{}})

      assert solution.label == "Keyword DRAGON alphabet"
      assert MixedAlphabet.decode(text, solution.params) == @short
    end

    test "skips keyword alphabets contradicting the user's letters" do
      text = MixedAlphabet.encode(@short, %{mapping: keyword_mapping("DRAGON")})
      # D is the cipher letter of A: say it's Z instead.
      {:ok, solution} = MixedAlphabet.solve(text, %{mapping: %{"D" => "Z"}})

      assert solution.label == "Solver"
      assert solution.params.mapping["D"] == "Z"
      assert solution.reason =~ "1 letter(s) were kept"
    end
  end

  describe "solvers start from the current settings" do
    test "keyword: a long keyword the search misses alone is kept" do
      text = KeywordSubstitution.encode(@plain, %{keyword: "ZYXWVUTSQP"})

      {:ok, alone} = KeywordSubstitution.solve(text, %{keyword: ""})
      refute KeywordSubstitution.decode(text, alone.params) == @plain

      {:ok, solution} = KeywordSubstitution.solve(text, %{keyword: "ZYXWVUTSQP"})
      assert KeywordSubstitution.decode(text, solution.params) == @plain
    end

    test "Vigenère: a long key the search misses alone, fixed from one wrong letter" do
      text = Vigenere.encode(@plain, %{key: "PLKMJNHBGV"})

      {:ok, alone} = Vigenere.solve(text, %{key: ""})
      refute alone.params.key == "PLKMJNHBGV"

      {:ok, solution} = Vigenere.solve(text, %{key: "PLKMJNHBGA"})
      assert solution.params.key == "PLKMJNHBGV"
    end
  end

  describe "symbol substitution" do
    test "recognizes texts of symbols" do
      assert SymbolSubstitution.recognize("☀♪Θ ♠Φ☎Θ ♣♥♦") =~ "symbols"
      assert SymbolSubstitution.recognize("hello world") == nil
      # Morse code's.
      assert SymbolSubstitution.recognize("... --- ... / ...") == nil
    end
  end
end
