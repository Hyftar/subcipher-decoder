defmodule Subcipher.Steps.Ciphers.Morse do
  @moduledoc """
  International Morse code. Letters are separated by a space; words by "/",
  "|" or several spaces; lines are decoded separately. Accepts "." "•" "∙"
  for dots and "-" "–" "—" "−" "_" for dashes, or any two symbols set as
  `dot` and `dash` ("0" and "1", "a" and "b"…). Words that aren't Morse
  are left as they are; unknown codes become "·".

  With `letters: "joined"`, letters aren't separated (only words, by spaces,
  "/" or "|"): where each letter starts is guessed, picking the most
  English-looking split (`Subcipher.English` quadgrams, beam search).
  """
  use Subcipher.Steps.Cipher

  @codes %{
    ".-" => "A",
    "-..." => "B",
    "-.-." => "C",
    "-.." => "D",
    "." => "E",
    "..-." => "F",
    "--." => "G",
    "...." => "H",
    ".." => "I",
    ".---" => "J",
    "-.-" => "K",
    ".-.." => "L",
    "--" => "M",
    "-." => "N",
    "---" => "O",
    ".--." => "P",
    "--.-" => "Q",
    ".-." => "R",
    "..." => "S",
    "-" => "T",
    "..-" => "U",
    "...-" => "V",
    ".--" => "W",
    "-..-" => "X",
    "-.--" => "Y",
    "--.." => "Z",
    "-----" => "0",
    ".----" => "1",
    "..---" => "2",
    "...--" => "3",
    "....-" => "4",
    "....." => "5",
    "-...." => "6",
    "--..." => "7",
    "---.." => "8",
    "----." => "9",
    ".-.-.-" => ".",
    "--..--" => ",",
    "..--.." => "?",
    ".----." => "'",
    "-.-.--" => "!",
    "-..-." => "/",
    "-.--." => "(",
    "-.--.-" => ")",
    ".-..." => "&",
    "---..." => ":",
    "-.-.-." => ";",
    "-...-" => "=",
    ".-.-." => "+",
    "-....-" => "-",
    ".-..-." => "\"",
    ".--.-." => "@"
  }

  @impl true
  def type, do: "morse"

  @impl true
  def name, do: "Morse code"

  @impl true
  def description,
    do:
      "Dots and dashes (or any two symbols); letters separated by a space, words by “/”, “|” or several spaces."

  @impl true
  def osrs_usage,
    do: "Easter eggs all over Gielinor: bank booths, gravestones, Alliance records, contracts…"

  @impl true
  def fields do
    [
      %{
        name: :dot,
        type: :string,
        label: "Dot symbol",
        default: "",
        help: "The character standing for dots; empty for “.” (or •)."
      },
      %{
        name: :dash,
        type: :string,
        label: "Dash symbol",
        default: "",
        help: "The character standing for dashes; empty for “-” (or –, _)."
      },
      %{
        name: :letters,
        type: :select,
        label: "Letters",
        default: "spaced",
        options: [
          {"Separated by spaces", "spaced"},
          {"Run together (letter breaks guessed)", "joined"}
        ],
        help:
          "Run together: spaces separate words only, and where each letter starts is guessed from how English the result reads."
      }
    ]
  end

  @impl true
  def validate(changeset) do
    changeset
    |> validate_length(:dot, max: 1)
    |> validate_length(:dash, max: 1)
    |> validate_change(:dash, fn :dash, dash ->
      dot = get_field(changeset, :dot)

      if dash not in [nil, ""] and dash == dot,
        do: [dash: "must differ from the dot symbol"],
        else: []
    end)
  end

  @impl true
  # Letters separated by a space (none when run together), words by " / ".
  # Characters without a Morse code become the error signal (8 dots),
  # decoded as unknown. Run-together Morse is ambiguous: decoding it is a
  # guess, which may not give the text back.
  def encode(text, params) do
    letters = Map.new(@codes, fn {code, char} -> {char, code} end)
    {dot, dash} = symbols(params)
    letter_gap = if joined?(params), do: "", else: " "

    text
    |> String.split("\n")
    |> Enum.map_join("\n", fn line ->
      line
      |> String.split(~r/\s+/u, trim: true)
      |> Enum.map_join(" / ", fn word ->
        word
        |> String.upcase()
        |> String.graphemes()
        |> Enum.map_join(letter_gap, fn char ->
          letters
          |> Map.get(char, "........")
          |> String.replace([".", "-"], &if(&1 == ".", do: dot, else: dash))
        end)
      end)
    end)
  end

  @impl true
  def decode(text, params) do
    text |> String.split("\n") |> Enum.map_join("\n", &decode_line(&1, params))
  end

  defp joined?(params), do: Map.get(params, :letters) == "joined"

  defp decode_line(line, params) do
    # Run together, any space separates words.
    separators = if joined?(params), do: ~r/\s*[\/|]\s*|\s+/u, else: ~r/\s*[\/|]\s*|\s{2,}/u
    words = line |> String.trim() |> String.split(separators, trim: true)

    cond do
      words == [] or not Enum.all?(words, &morse?(&1, params)) -> line
      joined?(params) -> words |> Enum.map(&normalize(&1, params)) |> segment() |> Enum.join(" ")
      true -> Enum.map_join(words, " ", &decode_word(&1, params))
    end
  end

  # The dot and dash symbols used: the custom ones, else the usual ones.
  defp symbols(params) do
    {blank_or(Map.get(params, :dot), "."), blank_or(Map.get(params, :dash), "-")}
  end

  defp blank_or(value, default) when value in [nil, ""], do: default
  defp blank_or(value, _default), do: value

  # Dots as ".", dashes as "-". Custom symbols come first: they may be
  # characters that are usually the other one (a swapped "-" and ".").
  defp normalize(token, params) do
    dot = Map.get(params, :dot)
    dash = Map.get(params, :dash)

    token
    |> String.graphemes()
    |> Enum.map_join(fn
      ^dot -> "."
      ^dash -> "-"
      c when c in ~w(• ∙) -> "."
      c when c in ~w(– — − _) -> "-"
      c -> c
    end)
  end

  defp morse?(word, params), do: normalize(word, params) =~ ~r/^[.\- ]+$/

  defp decode_word(word, params) do
    word
    |> normalize(params)
    |> String.split(" ", trim: true)
    |> Enum.map_join(&Map.get(@codes, &1, Alphabet.unknown()))
  end

  ## Run-together letters

  # Letter codes only: digits and punctuation would make the split even more
  # ambiguous.
  @letter_codes for {code, <<c>>} <- @codes, c in ?A..?Z, into: %{}, do: {code, c - ?A}
  @longest_letter 4

  # Splits kept at each position of a word: the most English ones.
  @beam 128

  # Weights of the scores of a split: its 4-letter sequences (log10 of their
  # frequency, `Subcipher.English.quadgram/4`), plus a bonus for each
  # quadgram (without it, splits into fewer, longer letters always win),
  # and the dictionary score of each word (`Subcipher.English.words_score/1`).
  @per_quadgram 0.0
  @word_weight 1.0

  # Words not in the dictionary cost this much per letter on top: a split
  # into one long unknown word must lose to real words.
  @unknown_per_letter -1.5

  # Word breaks are guessed in lines without any, from this many symbols
  # (about 10 letters): shorter ones are more likely a single word.
  @guess_breaks_from 30

  # The first letters of a line, before a full quadgram: English letter
  # frequencies (log10).
  @first_letters Subcipher.Steps.Alphabet.english_percentages()
                 |> Enum.map(&:math.log10(&1 / 100))
                 |> List.to_tuple()

  # The most English split of `words` (strings of "." and "-") into letters,
  # one string per word. A line without word breaks gets them guessed too
  # (dictionary words make a split likelier). A split is {score, last three letters (most recent
  # first), words done (reversed), letters of the current word (reversed)}.
  defp segment(words) do
    guess_breaks? = match?([word] when byte_size(word) >= @guess_breaks_from, words)

    {_score, _context, done, _letters} =
      words
      |> Enum.reduce([{0.0, [], [], []}], fn word, splits ->
        word
        |> segment_word(splits, guess_breaks?)
        |> Enum.map(&end_word/1)
        |> keep_best(fn {_, context, _, _} -> context end)
      end)
      |> Enum.max_by(&elem(&1, 0))

    done
    |> Enum.reverse()
    |> Enum.map(fn letters -> for l <- letters, into: "", do: <<?A + l>> end)
  end

  # Extends `splits` through `word`, letter by letter: the splits reaching
  # its end.
  defp segment_word(word, splits, guess_breaks?) do
    size = byte_size(word)

    0..(size - 1)//1
    |> Enum.reduce(%{0 => splits}, fn position, buckets ->
      {here, buckets} = Map.pop(buckets, position, [])
      # Splits whose current word is the same have the same future: only
      # the best one is extended.
      here = keep_best(here, fn {_, context, _, letters} -> {context, letters} end)

      # A word may end here too (not before its first letter).
      here =
        if guess_breaks? and position > 0,
          do: here ++ for({_, _, _, [_ | _]} = split <- here, do: end_word(split)),
          else: here

      for {score, context, done, letters} <- here,
          length <- 1..min(@longest_letter, size - position)//1,
          letter = Map.get(@letter_codes, binary_part(word, position, length)),
          letter != nil,
          reduce: buckets do
        buckets ->
          # Until it ends, the current word counts as unknown: splits ending
          # words and splits going on compare fairly.
          n = length(letters)

          pending = unknown_word(n + 1) - unknown_word(n)

          next =
            {score + gain(context, letter) + @word_weight * pending,
             Enum.take([letter | context], 3), done, [letter | letters]}

          Map.update(buckets, position + length, [next], &[next | &1])
      end
    end)
    |> Map.get(size, [])
  end

  # The current word of a split is complete: its dictionary score counts.
  defp end_word({score, context, done, letters}) do
    pending = unknown_word(length(letters))
    letters = Enum.reverse(letters)
    word_score = Subcipher.English.word_score(letters, @unknown_per_letter) - pending
    {score + @word_weight * word_score, context, [letters | done], []}
  end

  # The score of a word of `n` letters not in the dictionary.
  defp unknown_word(0), do: 0.0
  defp unknown_word(n), do: Subcipher.English.unknown_word_score(n, @unknown_per_letter)

  # The best split for each key, at most @beam of them.
  defp keep_best(splits, key) do
    splits
    |> Enum.sort_by(&elem(&1, 0), :desc)
    |> Enum.uniq_by(key)
    |> Enum.take(@beam)
  end

  # Contexts are the last letters, most recent first.
  defp gain([c, b, a], letter),
    do: Subcipher.English.quadgram(a, b, c, letter) + @per_quadgram

  defp gain(_context, letter), do: elem(@first_letters, letter)

  ## Guessing the settings

  @usual_symbols ~w(. - • ∙ – — − _)

  @doc """
  The distinct symbols of `text` (characters other than whitespace and the
  word separators "/" and "|"), most frequent first.
  """
  def distinct_symbols(text) do
    text
    |> Alphabet.symbol_frequencies()
    |> Enum.map(&elem(&1, 0))
    |> Enum.reject(&(&1 in ["/", "|"]))
  end

  # A text of one or two symbols can be Morse: try each symbol as the dot
  # and as the dash, letters separated by spaces or, when that mostly gives
  # no valid code, run together. Best first.
  @impl true
  def suggestions(input, _params) do
    case distinct_symbols(input) do
      symbols when length(symbols) in 1..2 ->
        symbols
        |> assignments()
        |> Enum.flat_map(fn params ->
          spaced = Map.put(params, :letters, "spaced")
          output = decode(input, spaced)
          {decoded, total} = code_counts(input, output)
          tried = [{spaced, output}]

          if decoded * 2 <= total do
            joined = Map.put(params, :letters, "joined")
            tried ++ [{joined, decode(input, joined)}]
          else
            tried
          end
        end)
        |> Enum.map(fn {params, output} -> {rank(input, params, output), params, output} end)
        |> Enum.sort_by(&elem(&1, 0), :desc)
        |> Enum.map(fn {_, params, output} ->
          %{label: label(params), params: params, reason: reason(input, symbols, params, output)}
        end)

      _ ->
        []
    end
  end

  # Settings reading the symbols as dots and dashes, both ways round. The
  # usual reading ("." dots, "-" dashes) keeps the default (empty) symbols.
  defp assignments([a]), do: [%{dot: a, dash: ""}, %{dot: "", dash: a}] |> Enum.map(&usual/1)
  defp assignments([a, b]), do: [%{dot: a, dash: b}, %{dot: b, dash: a}] |> Enum.map(&usual/1)

  defp usual(%{dot: dot, dash: dash} = params) do
    plain_dot = dot in ["", "." | ~w(• ∙)]
    plain_dash = dash in ["", "-" | ~w(– — − _)]
    if plain_dot and plain_dash, do: %{params | dot: "", dash: ""}, else: params
  end

  defp usual?(params), do: params.dot == "" and params.dash == ""

  # Most valid codes (the share of them) first, letters separated by spaces before run together
  # (a guess). Readings of a text the same way give as many letters: on a
  # long text, the most English one wins (by its 4-letter sequences); a
  # short one says too little, so the usual reading wins, then the most
  # English (by dictionary words when too short to score: SOS, not OSO).
  @long_enough 12

  defp rank(input, params, output) do
    {decoded, total} = code_counts(input, output)
    letters = Subcipher.English.letters(output)

    english =
      Subcipher.English.score_per_quadgram(letters) ||
        output
        |> String.split(~r/\s+/u, trim: true)
        |> Enum.map(&Subcipher.English.letters/1)
        |> Subcipher.English.words_score()

    long_english = if length(letters) >= @long_enough, do: english, else: 0.0

    valid_share = if total > 0, do: decoded / total, else: 0.0

    {total > 0 and decoded == total, not joined?(params), valid_share, long_english,
     usual?(params), english}
  end

  # How many letter codes of the input decoded to a known character, of
  # how many.
  defp code_counts(input, output) do
    if normalize_blank(output) == normalize_blank(input) do
      {0, 0}
    else
      decoded = output |> String.graphemes() |> Enum.reject(&(&1 =~ ~r/^\s$/u))
      {Enum.count(decoded, &(&1 != Alphabet.unknown())), length(decoded)}
    end
  end

  defp normalize_blank(text), do: String.replace(text, ~r/\s+/u, "")

  defp label(params) do
    symbols =
      case params do
        %{dot: "", dash: ""} -> "Dots and dashes"
        %{dot: dot, dash: ""} -> "“#{dot}” as dots"
        %{dot: "", dash: dash} -> "“#{dash}” as dashes"
        %{dot: dot, dash: dash} -> "“#{dot}” dots, “#{dash}” dashes"
      end

    if joined?(params), do: symbols <> ", run together", else: symbols
  end

  defp reason(input, symbols, params, output) do
    {decoded, total} = code_counts(input, output)

    made_of =
      case symbols do
        [a] -> "The text is made of a single symbol, “#{a}”"
        [a, b] -> "The text is made of only two symbols, “#{a}” and “#{b}”"
      end

    cond do
      joined?(params) ->
        made_of <>
          ", without spaces between letters: where each letter starts was guessed, " <>
          "picking the most English-looking split. Run-together Morse is ambiguous: check the result."

      total == 0 ->
        made_of <> ", but its groups aren't Morse codes."

      decoded == total ->
        made_of <> ", and read this way, all #{total} groups are valid Morse codes."

      true ->
        made_of <> "; read this way, #{decoded} of #{total} groups are valid Morse codes."
    end
  end

  @doc """
  Whether `input` is unmistakably Morse: one or two symbols (word
  separators aside), every group of which is a valid Morse code read one
  way, or run together (any one or two symbols can be read so). Returns
  why, or nil.
  """
  @impl true
  def recognize(input) do
    symbols = distinct_symbols(input)
    usual_symbols? = Enum.all?(symbols, &(&1 in @usual_symbols))

    with [best | _] <- suggestions(input, %{}),
         output = decode(input, best.params),
         {decoded, total} when total > 0 and decoded == total <- code_counts(input, output) do
      kind =
        if usual_symbols?,
          do: "only dots and dashes",
          else: "only #{Enum.map_join(symbols, " and ", &"“#{&1}”")}"

      if joined?(best.params),
        do:
          "The text has #{kind}, without spaces between letters: Morse code run together " <>
            "(where each letter starts was guessed).",
        else: "The text has #{kind}, and every group of them is a valid Morse code."
    else
      _ -> nil
    end
  end
end
