defmodule Subcipher.GuesserTest do
  use ExUnit.Case, async: true

  alias Subcipher.Guesser

  alias Subcipher.Steps.Ciphers.{
    Atbash,
    Caesar,
    KeywordSubstitution,
    LetterNumbers,
    MixedAlphabet,
    Morse,
    Reverse,
    Route,
    Vigenere
  }

  @plain "In the beginning there was nothing but darkness and the gods fought over " <>
           "the world until Guthix put them to sleep and shaped the land"

  defp winner(text) do
    {:ok, %{guesses: [best | _]}} = Guesser.guess(text)
    best
  end

  for {cipher, params} <- [
        {Caesar, %{shift: 7}},
        {Atbash, %{}},
        {Vigenere, %{key: "LEMON"}},
        {KeywordSubstitution, %{keyword: "FAITH"}},
        {Morse, %{}},
        {LetterNumbers, %{first: "1"}},
        {Reverse, %{mode: "text"}},
        {Route, %{width: 5, route: "zigzag", corner: "top_left", null: "X"}}
      ] do
    test "recognises #{inspect(cipher)}" do
      cipher = unquote(cipher)
      best = winner(cipher.encode(@plain, unquote(Macro.escape(params))))

      assert best.cipher == cipher
      assert best.fit >= Guesser.readable()
      assert best.output =~ ~r/guthix/i
    end
  end

  test "keeps the guessed settings, defaults included" do
    best = winner(Caesar.encode(@plain, %{shift: 7}))
    assert best.params == %{shift: 7}
  end

  test "a simpler cipher wins over one reaching the same result" do
    {:ok, %{guesses: guesses}} = Guesser.guess(Atbash.encode(@plain, %{}))
    mixed = Enum.find(guesses, &(&1.cipher == MixedAlphabet))

    assert hd(guesses).cipher == Atbash
    assert mixed.same_as == Atbash
  end

  test "hints at a shuffled alphabet when no suggestion reads like English" do
    shuffled =
      Map.new(Enum.zip(Enum.map(?A..?Z, &<<&1>>), String.graphemes("QWERTYUIOPASDFGHJKLZXCVBNM")))

    assert {:ok, %{hint: %{cipher: MixedAlphabet}} = result} =
             Guesser.guess(MixedAlphabet.encode(@plain, %{mapping: shuffled}))

    refute Enum.any?(result.guesses, &(&1.fit >= Guesser.readable()))
  end

  test "tells when the text already reads like English" do
    assert {:ok, %{plain: true}} = Guesser.guess(@plain)
    assert {:ok, %{plain: false}} = Guesser.guess(Caesar.encode(@plain, %{shift: 3}))
  end

  test "recognizes Morse code too short to score, in any two symbols" do
    for text <- ["... --- ...", "000 111 000", "aaa bbb aaa"] do
      best = winner(text)
      assert best.cipher == Morse
      assert best.output == "SOS"
      assert best.fit == nil
      assert best.recognized =~ "valid Morse code"
      assert Guesser.readable?(best)
    end
  end

  test "recognizes Morse code with letters run together" do
    best = winner("-.--.--...--.-")
    assert best.cipher == Morse
    assert best.params.letters == "joined"
    assert best.recognized =~ "run together"

    assert winner("......-...-..---.-----.-..-..-..").output == "HELLO WORLD"
  end

  test "trusts the cipher's reading of a recognized format" do
    assert winner("... --- ... / ...").output == "SOS S"
  end

  test "recognizes letter numbers" do
    best = winner("8 5 12 12 15")
    assert best.cipher == LetterNumbers
    assert best.output == "HELLO"
    assert best.recognized =~ "1 to 26"
  end

  test "the deep pass solves what the quick pass can't" do
    for cipher <- [KeywordSubstitution, MixedAlphabet, Vigenere] do
      [sample] = Subcipher.GuesserSamples.samples(cipher, 80, 1)

      {:ok, %{guesses: [quick | _]}} = Guesser.guess(sample.text)
      {:ok, %{guesses: [best | _]}} = Guesser.guess(sample.text, deep: true)

      refute Subcipher.GuesserSamples.decoded?(quick.output, sample.plain) and
               quick.cipher == cipher

      assert best.cipher == cipher
      assert best.deep
      assert Subcipher.GuesserSamples.decoded?(best.output, sample.plain)
    end
  end

  test "benchmark slice: every cipher at 80 letters, with the deep pass" do
    Subcipher.GuesserSamples.ciphers()
    |> Enum.flat_map(&Subcipher.GuesserSamples.samples(&1, 80, 1, 7))
    |> Task.async_stream(
      fn sample ->
        {:ok, %{guesses: [best | _]}} = Guesser.guess(sample.text, deep: true)
        {sample, best}
      end,
      timeout: :infinity
    )
    |> Enum.each(fn {:ok, {sample, best}} ->
      assert {best.cipher, Subcipher.GuesserSamples.decoded?(best.output, sample.plain)} ==
               {sample.cipher, true},
             "#{inspect(sample.cipher)} sample #{inspect(sample.text)}"
    end)
  end

  test "refuses texts too long to guess" do
    assert Guesser.guess(String.duplicate("abcde ", 1100)) == {:error, :too_long}
  end

  test "needs a few characters" do
    assert Guesser.guess("ab c") == {:error, :too_short}
    assert Guesser.guess("hello") == {:error, :too_short}
  end
end
