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
end
