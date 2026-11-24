defmodule Subcipher.GuesserSamples do
  @moduledoc """
  Encrypted samples to measure the guesser (`Subcipher.Guesser`): English
  plain texts of a given length, encrypted with each cipher and a random
  key. Seeded: the same arguments give the same samples.

  Used by `bench/guesser.exs` and the guesser tests.
  """

  alias Subcipher.English

  alias Subcipher.Steps.Ciphers.{
    Ascii,
    Atbash,
    Caesar,
    KeywordSubstitution,
    LetterNumbers,
    MixedAlphabet,
    Morse,
    Reverse,
    Route,
    SymbolSubstitution,
    Unicode,
    Vigenere
  }

  @sentences [
    "Meet me at the old mill at midnight and bring the map with you",
    "The treasure is buried beneath the third oak tree north of the river",
    "Speak to the wise old man in the village before the sun goes down",
    "Dig near the fountain in the market square when the bell rings twice",
    "The guards change their watch at dawn so we must move quickly tonight",
    "Follow the path through the forest until you reach the ruined tower",
    "Nobody must know that the key is hidden inside the broken lantern",
    "Our friend in the castle will open the gate if you give the signal",
    "The ship leaves the harbour at first light with the stolen gold aboard",
    "Remember to bring a rope a torch and enough food for three days",
    "The wizard said that the answer lies where the two rivers meet",
    "Look for a stone with a strange mark carved on its eastern side",
    "Every evening the old fisherman tells stories about the sea monster",
    "When the moon is full the door in the cliff will open for a short time",
    "Please send more soldiers to the northern border as soon as you can",
    "The library holds a book that explains how to read this ancient script",
    "Burn this letter after reading it and tell no one what it says",
    "The merchant sold me a ring that glows faintly in the dark",
    "Travel east for two days and then ask the farmer about the cave",
    "I have hidden the second half of the map under the floor of the inn"
  ]

  @symbols ~w(☀ ♪ Θ ♠ Φ ☎ ★ ♣ ♥ ♦ ☂ ✈ ⚓ ☯ ⚑ ✿ ☘ ⌘ Ω Δ Ψ Σ Λ Ξ Π Γ)
  @names ~w(VARROCK LUMBRIDGE FALADOR ZAMORAK GUTHIX ARDOUGNE MORYTANIA KARAMJA)

  @doc "The ciphers sampled."
  def ciphers,
    do: [
      Atbash,
      Morse,
      LetterNumbers,
      Ascii,
      Unicode,
      Reverse,
      Caesar,
      KeywordSubstitution,
      Route,
      Vigenere,
      MixedAlphabet,
      SymbolSubstitution
    ]

  @doc """
  `count` samples of `cipher` at about `letters` letters:
  `%{cipher: module, params: map, plain: text, text: encrypted}`.
  """
  def samples(cipher, letters, count, seed \\ 1) do
    :rand.seed(:exsss, {seed, letters, :erlang.phash2(cipher)})

    for _ <- 1..count do
      plain = plain_text(letters)
      # On ASCII text, the Unicode ciphers write what the ASCII ones do.
      plain = if cipher == Unicode, do: plain <> " ☀", else: plain
      params = random_params(cipher)
      %{cipher: cipher, params: params, plain: plain, text: cipher.encode(plain, params)}
    end
  end

  # Random sentences cut at the last word fitting in `letters` letters.
  defp plain_text(letters) do
    @sentences
    |> Enum.shuffle()
    |> Enum.join(" ")
    |> String.split(" ")
    |> Enum.reduce_while({[], 0}, fn word, {words, count} ->
      count = count + String.length(word)

      if count > letters and words != [],
        do: {:halt, {words, count}},
        else: {:cont, {[word | words], count}}
    end)
    |> elem(0)
    |> Enum.reverse()
    |> Enum.join(" ")
  end

  defp random_params(Atbash), do: %{}

  defp random_params(Ascii),
    do: %{base: Enum.random(~w(10 16 2)), width: Enum.random(["8", "7"])}

  defp random_params(Unicode),
    do: %{base: Enum.random(~w(10 16 2)), encoding: Enum.random(["utf8", "code_points"])}

  defp random_params(Morse), do: %{dot: "", dash: "", letters: "spaced"}
  defp random_params(LetterNumbers), do: %{first: Enum.random(["0", "1"])}
  defp random_params(Reverse), do: %{mode: Enum.random(~w(lines words text))}
  defp random_params(Caesar), do: %{shift: Enum.random(1..25)}
  defp random_params(KeywordSubstitution), do: %{keyword: random_key()}
  defp random_params(Vigenere), do: %{key: random_key()}

  defp random_params(Route) do
    %{
      width: Enum.random(3..8),
      route: Enum.random(~w(columns zigzag spiral_clockwise spiral_anticlockwise)),
      corner: Enum.random(~w(top_left top_right bottom_right bottom_left)),
      null: "X"
    }
  end

  defp random_params(MixedAlphabet) do
    letters = Enum.map(?A..?Z, &<<&1>>)
    %{mapping: letters |> Enum.zip(Enum.shuffle(letters)) |> Map.new()}
  end

  defp random_params(SymbolSubstitution) do
    %{mapping: @symbols |> Enum.shuffle() |> Enum.zip(Enum.map(?A..?Z, &<<&1>>)) |> Map.new()}
  end

  # A dictionary word, an OSRS name or random letters, a third each.
  defp random_key do
    case :rand.uniform(3) do
      1 ->
        English.dictionary(4, 9)
        |> Enum.take(3000)
        |> Enum.random()
        |> Enum.map_join(&<<?A + &1>>)

      2 ->
        Enum.random(@names)

      3 ->
        for _ <- 1..Enum.random(3..7), into: "", do: <<?A + :rand.uniform(26) - 1>>
    end
  end

  @doc """
  Whether `output` decodes `plain`: at least 90% of its letters match
  (case, spacing and punctuation aside; Route may add trailing nulls).
  """
  def decoded?(output, plain) do
    want = English.letters(plain)
    got = English.letters(output)
    matching = Enum.zip(want, got) |> Enum.count(fn {a, b} -> a == b end)
    want != [] and matching >= 0.9 * length(want)
  end
end
