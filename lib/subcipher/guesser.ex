defmodule Subcipher.Guesser do
  @moduledoc """
  Guesses which cipher encoded a text, in two passes:

    * the quick pass (`quick/1`, well under a second): every cipher tries
      its suggestions (`c:Subcipher.Steps.Cipher.suggestions/2`; ciphers
      without suggestions try their default settings);
    * the deep pass (`deep/2`, seconds, one cipher at a time): the ciphers
      with a solver (`c:Subcipher.Steps.Cipher.solve/2`: mixed alphabet,
      symbol substitution, keyword substitution, Vigenère) search their key.

  Each cipher keeps its best result (`merge/2`), and `result/2` ranks them.
  A result is scored by how English it reads (the average log probability
  of its 4-letter sequences, `Subcipher.English.score_per_quadgram/1`),
  minus the size of the key space it was picked from
  (`Subcipher.KeySpace`) spread over its quadgrams: a mixed alphabet can
  make a short text read like English by chance, a Caesar shift can't, so
  the bigger key has to fit much better. On a tie the simpler cipher wins.

  Results that leave the text unchanged decode nothing and are dropped.
  Some ciphers recognize their own format (`c:Subcipher.Steps.Cipher.recognize/1`:
  only dots and dashes, only numbers up to 26, only symbols): they rank
  first, even when their result is too short to score (“SOS”).

  When no result reads like English, the letter statistics of the text
  give a `hint` of the kind of cipher instead.
  """

  alias Subcipher.{English, KeySpace, Steps}
  alias Subcipher.Steps.Alphabet

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

  # The ciphers guessed, simplest first (on equal scores, the first wins).
  # The anagram is left out: its settings are a free order of the letters.
  @ciphers [
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

  # Ciphers with a deep pass (a solver).
  @deep [MixedAlphabet, SymbolSubstitution, KeywordSubstitution, Vigenere]

  # Weight of the key space penalty (tuned with bench/guesser.exs).
  @key_weight 2.0

  # Average log10 probability per quadgram of English text, and of random
  # letters: the ends of the fit scale (0..1) shown to the user.
  @english -4.5
  @random -6.4

  # Fewer characters than this say too little to guess, unless a cipher
  # recognizes its format; longer texts are refused.
  @min_characters 8
  @max_characters 5000

  # A result fitting at least this well reads like English.
  @readable 0.75

  # Letter statistics need about this many letters to mean something.
  @min_hint_letters 40

  # Solvers need about this many letters.
  @min_deep_letters 8

  @type candidate :: %{
          cipher: module(),
          label: String.t(),
          params: map(),
          reason: String.t(),
          output: String.t(),
          preview: String.t(),
          score: float(),
          fit: float() | nil,
          recognized: String.t() | nil,
          deep: boolean()
        }

  @type guess :: %{
          required(:same_as) => module() | nil,
          optional(atom()) => term()
        }

  @type result :: %{
          guesses: [guess()],
          hint: %{cipher: module(), reason: String.t()} | nil,
          plain: boolean()
        }

  @doc "The ciphers that can be guessed, simplest first."
  def ciphers, do: @ciphers

  @doc "The fit (0..1) from which a result reads like English."
  def readable, do: @readable

  @doc """
  Whether a guess decodes the text: its format was recognized, or its result
  reads like English.
  """
  def readable?(%{recognized: reason}) when is_binary(reason), do: true
  def readable?(%{fit: fit}) when is_float(fit), do: fit >= @readable
  def readable?(_guess), do: false

  @doc """
  Guesses the cipher of `text`: the quick pass, then (with `deep: true`) the
  deep pass of every cipher it applies to, in parallel. The ranked
  `result/2`, or `{:error, :too_short | :too_long}`.
  """
  @spec guess(String.t(), keyword()) :: {:ok, result()} | {:error, :too_short | :too_long}
  def guess(text, opts \\ []) do
    with {:ok, candidates} <- quick(text) do
      candidates =
        if Keyword.get(opts, :deep, false) do
          text
          |> deep_ciphers()
          |> Task.async_stream(&deep(text, &1), timeout: :infinity)
          |> Enum.reduce(candidates, fn {:ok, candidate}, acc -> merge(acc, candidate) end)
        else
          candidates
        end

      {:ok, result(text, candidates)}
    end
  end

  @doc """
  The quick pass: the best suggestion of each cipher decoding something.
  `{:error, :too_short}` when the text has too few characters to tell and
  no cipher recognizes it, `{:error, :too_long}` above #{@max_characters}.
  """
  @spec quick(String.t()) :: {:ok, [candidate()]} | {:error, :too_short | :too_long}
  def quick(text) when is_binary(text) do
    length = text |> normalize() |> String.length()

    if length > @max_characters do
      {:error, :too_long}
    else
      candidates =
        @ciphers
        |> Task.async_stream(&best(&1, text), timeout: :infinity)
        |> Enum.flat_map(fn {:ok, result} -> List.wrap(result) end)

      if length < @min_characters and not Enum.any?(candidates, &is_binary(&1.recognized)),
        do: {:error, :too_short},
        else: {:ok, candidates}
    end
  end

  @doc "The ciphers whose deep pass is worth running on `text`."
  def deep_ciphers(text) do
    letters = text |> English.letters() |> length()

    Enum.filter(@deep, fn
      SymbolSubstitution -> is_binary(SymbolSubstitution.recognize(text))
      _letters_cipher -> letters >= @min_deep_letters
    end)
  end

  @doc """
  The deep pass of `cipher` (its solver) on `text`: a candidate, or nil when
  it finds nothing or takes longer than `timeout` ms.
  """
  @spec deep(String.t(), module(), timeout()) :: candidate() | nil
  def deep(text, cipher, timeout \\ :infinity) do
    task = Task.async(fn -> solve(cipher, text) end)

    case Task.yield(task, timeout) || Task.shutdown(task, :brutal_kill) do
      {:ok, candidate} -> candidate
      _ -> nil
    end
  end

  defp solve(cipher, text) do
    with true <- Steps.implements?(cipher, :solve, 2),
         {:ok, suggestion} <- cipher.solve(text, defaults(cipher)),
         candidate when candidate != nil <-
           candidate(cipher, text, suggestion, recognize(cipher, text)) do
      Map.put(candidate, :deep, true)
    else
      _ -> nil
    end
  end

  @doc """
  Adds `candidate` (nil for none) to `candidates`, keeping the better one
  of its cipher.
  """
  def merge(candidates, nil), do: candidates

  def merge(candidates, candidate) do
    case Enum.find(candidates, &(&1.cipher == candidate.cipher)) do
      nil -> candidates ++ [candidate]
      current when current.score >= candidate.score -> candidates
      current -> Enum.map(candidates, &if(&1 == current, do: candidate, else: &1))
    end
  end

  @doc """
  Ranks `candidates` (one per cipher) for `text` (see `t:result/0`):

    * `guesses` - best first: recognized formats, then by score; `same_as`
      is the better ranked cipher giving the very same result, if any;
    * `hint` - when no result reads like English, the cipher the letter
      statistics point to, and why (`nil` when they say nothing clear);
    * `plain` - whether the text already reads like English.
  """
  @spec result(String.t(), [candidate()]) :: result()
  def result(text, candidates) do
    order = @ciphers |> Enum.with_index() |> Map.new()

    guesses =
      candidates
      |> Enum.sort_by(&{is_binary(&1.recognized), &1.score, -order[&1.cipher]}, :desc)
      |> mark_duplicates()

    %{
      guesses: guesses,
      hint: if(Enum.any?(guesses, &readable?/1), do: nil, else: hint(text)),
      plain: (fit(English.score_per_quadgram(English.letters(text))) || 0.0) >= @readable
    }
  end

  ## Quick pass

  # The cipher's best suggestion, or nil when none decodes anything.
  defp best(cipher, text) do
    recognized = recognize(cipher, text)

    cipher
    |> suggestions(text)
    |> Enum.with_index()
    |> Enum.flat_map(fn {suggestion, rank} ->
      case candidate(cipher, text, suggestion, recognized) do
        nil -> []
        candidate -> [Map.put(candidate, :rank, rank)]
      end
    end)
    # Fewest undecodable characters first (Morse codes that don't exist),
    # then the best score. A cipher recognizing its format knows best how
    # to read it: its own order of suggestions wins (on a short text, the
    # usual Morse reading rather than a luckier-scoring swapped one).
    |> Enum.max_by(
      &{-count_unknown(&1.output), if(recognized, do: -&1.rank, else: &1.score)},
      fn -> nil end
    )
    |> then(&(&1 && &1 |> Map.delete(:rank) |> Map.put(:deep, false)))
  end

  defp suggestions(cipher, text) do
    if Steps.implements?(cipher, :suggestions, 2) do
      cipher.suggestions(text, defaults(cipher))
    else
      [%{label: cipher.name(), params: %{}, reason: cipher.description()}]
    end
  end

  defp recognize(cipher, text),
    do: if(Steps.implements?(cipher, :recognize, 1), do: cipher.recognize(text))

  defp defaults(cipher), do: Map.new(cipher.fields(), &{&1.name, &1.default})

  # A suggestion as a candidate, or nil when its result changes nothing or
  # is too short to score (unless the format was recognized).
  defp candidate(cipher, text, suggestion, recognized) do
    params = Map.merge(defaults(cipher), suggestion.params)
    output = cipher.decode(text, params)
    letters = English.letters(output)
    per_quadgram = English.score_per_quadgram(letters)

    if normalize(output) != normalize(text) and (is_float(per_quadgram) or is_binary(recognized)) do
      %{
        cipher: cipher,
        label: suggestion.label,
        reason: suggestion.reason,
        params: params,
        output: output,
        preview: Steps.preview(output),
        score: score(per_quadgram, key_space(cipher, params, text), length(letters)),
        fit: fit(per_quadgram),
        recognized: recognized
      }
    end
  end

  # How English the result reads per quadgram, minus the key space spread
  # over its quadgrams. Results too short to score rank last, simplest key
  # first.
  defp score(nil, key_space, _letters), do: -99.0 - key_space

  defp score(per_quadgram, key_space, letters),
    do: per_quadgram - @key_weight * key_space / (letters - 3)

  @doc "Log10 of the number of keys `params` were picked from, for `cipher` on `text`."
  def key_space(cipher, params, text)
  def key_space(Atbash, _params, _text), do: 0.0
  # Dots and dashes either way round, letters spaced or run together.
  def key_space(Morse, _params, _text), do: KeySpace.choices(4)
  def key_space(LetterNumbers, _params, _text), do: KeySpace.choices(2)
  # Decimal, hexadecimal or binary (8 or 7 bits); UTF-8 bytes or code points.
  def key_space(Ascii, _params, _text), do: KeySpace.choices(4)
  def key_space(Unicode, _params, _text), do: KeySpace.choices(3 * 2)
  def key_space(Reverse, _params, _text), do: KeySpace.choices(3)
  def key_space(Caesar, _params, _text), do: KeySpace.choices(26)
  def key_space(Route, _params, _text), do: KeySpace.choices(19 * 16)

  def key_space(KeywordSubstitution, %{keyword: keyword}, _text),
    do:
      keyword
      |> English.letters()
      |> Enum.uniq()
      |> Enum.map(&<<?A + &1>>)
      |> Enum.join()
      |> KeySpace.word()

  def key_space(Vigenere, %{key: key}, _text), do: KeySpace.word(key || "")

  def key_space(MixedAlphabet, _params, text),
    do: text |> English.letters() |> Enum.uniq() |> length() |> KeySpace.permutation()

  def key_space(SymbolSubstitution, _params, text),
    do: text |> Alphabet.symbol_frequencies() |> length() |> KeySpace.permutation()

  def key_space(_cipher, _params, _text), do: 0.0

  defp count_unknown(output),
    do: output |> String.graphemes() |> Enum.count(&(&1 == Alphabet.unknown()))

  ## Ranking

  # Ciphers can reach the same result (a Vigenère key of one letter is a
  # Caesar shift): point to the better ranked one.
  defp mark_duplicates(guesses) do
    {marked, _} =
      Enum.map_reduce(guesses, %{}, fn guess, seen ->
        key = normalize(guess.output)
        {Map.put(guess, :same_as, seen[key]), Map.put_new(seen, key, guess.cipher)}
      end)

    marked
  end

  # What the letters of the text say about the cipher: transpositions keep
  # English letter frequencies; simple substitutions shuffle them but keep
  # how often letters repeat (index of coincidence); a Vigenère key flattens
  # both.
  defp hint(text) do
    count = text |> English.letters() |> length()

    if count < @min_hint_letters do
      nil
    else
      ioc = Alphabet.index_of_coincidence(text)
      distance = Alphabet.english_score(text) / count
      stats = "index of coincidence #{Float.round(ioc, 3)}; English ≈ 0.066, random ≈ 0.038"

      cond do
        distance < 1.5 ->
          %{
            cipher: Route,
            reason:
              "The letters are as frequent as in English, only out of order: " <>
                "the text was probably rearranged (route cipher, anagram…), not substituted."
          }

        ioc >= 0.05 ->
          %{
            cipher: MixedAlphabet,
            reason:
              "Letters repeat as often as in English (#{stats}) but aren't the usual ones: " <>
                "probably a simple substitution with a shuffled alphabet. " <>
                "Its solver (“Try to solve”) can find the alphabet."
          }

        ioc < 0.045 ->
          %{
            cipher: Vigenere,
            reason:
              "Letters repeat about as rarely as random ones (#{stats}): " <>
                "probably a cipher whose shift changes along the text, like Vigenère " <>
                "(its key may be too long for this text to find)."
          }

        true ->
          nil
      end
    end
  end

  defp fit(nil), do: nil

  defp fit(per_quadgram),
    do: ((per_quadgram - @random) / (@english - @random)) |> max(0.0) |> min(1.0)

  # The text without case or whitespace: what tells whether a result
  # changed anything.
  defp normalize(text), do: text |> String.upcase() |> String.replace(~r/\s+/u, "")
end
