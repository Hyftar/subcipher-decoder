defmodule Subcipher.Steps.Ciphers.Reverse do
  @moduledoc "Reversed text: by line, by word, or the whole text."
  use Subcipher.Steps.Cipher

  @impl true
  def type, do: "reverse"

  @impl true
  def name, do: "Reversed text"

  @impl true
  def description, do: "The text was written backwards."

  @impl true
  def osrs_usage,
    do: "Demonic Pacts League reveal; names spelled backwards (Yenrab, Lahsram, Erodoeht…)."

  @impl true
  def fields do
    [
      %{
        name: :mode,
        type: :select,
        label: "Reverse",
        default: "lines",
        options: [
          {"Each line", "lines"},
          {"Each word (word order kept)", "words"},
          {"The whole text (last line first)", "text"}
        ]
      }
    ]
  end

  @impl true
  def decode(text, %{mode: "text"}), do: String.reverse(text)

  def decode(text, %{mode: "lines"}) do
    text |> String.split("\n") |> Enum.map_join("\n", &String.reverse/1)
  end

  def decode(text, %{mode: "words"}) do
    # Splits on whitespace, keeping it, so spacing and line breaks survive.
    ~r/(\s+)/u
    |> Regex.split(text, include_captures: true)
    |> Enum.map_join(fn part -> if part =~ ~r/^\s+$/u, do: part, else: String.reverse(part) end)
  end

  # Reversing doesn't change letter frequencies: compare the modes by the
  # common English words and letter pairs they produce instead.
  @impl true
  def suggestions(input, _params) do
    if String.trim(input) == "" do
      []
    else
      [{"lines", "Each line"}, {"words", "Each word"}, {"text", "Whole text"}]
      |> Enum.map(fn {mode, label} ->
        output = decode(input, %{mode: mode})
        words = Alphabet.common_words(output)
        {{-length(words), -Alphabet.bigram_ratio(output)}, mode, label, output}
      end)
      |> Enum.sort()
      |> Enum.map(fn {_, mode, label, output} ->
        %{label: label, params: %{mode: mode}, reason: reason(output)}
      end)
    end
  end

  defp reason(output) do
    pairs =
      "#{round(Alphabet.bigram_ratio(output) * 100)}% of its letter pairs are common in English (English text: about 30–40%)"

    case Alphabet.words_hint(output) do
      nil -> "Reads as no common English word; " <> pairs <> "."
      hint -> "The result " <> hint <> "; " <> pairs <> "."
    end
  end
end
