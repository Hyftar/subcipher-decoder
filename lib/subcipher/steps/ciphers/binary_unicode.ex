defmodule Subcipher.Steps.Ciphers.BinaryUnicode do
  @moduledoc """
  Binary Unicode: each character written in binary, either as its UTF-8
  bytes (8 bits each, run together or not: ☀ = 11100010 10011000 10000000)
  or as its code point (one group per character: ☀ = 10011000000000). See
  `Subcipher.Steps.CodeUnits`.
  """
  use Subcipher.Steps.Cipher

  alias Subcipher.Steps.CodeUnits

  @encodings [{"UTF-8 bytes", "utf8"}, {"Code points", "code_points"}]

  @impl true
  def type, do: "binary_unicode"

  @impl true
  def name, do: "Binary (Unicode)"

  @impl true
  def description,
    do: "Each character written in binary: its UTF-8 bytes, 8 bits each, or its code point."

  @impl true
  def fields do
    [
      %{
        name: :encoding,
        type: :select,
        label: "Numbers are",
        default: "utf8",
        options: @encodings
      }
    ]
  end

  @impl true
  def encode(text, %{encoding: "utf8"}) do
    for(<<byte <- text>>, do: CodeUnits.format(byte, 2, 8)) |> Enum.join(" ")
  end

  def encode(text, %{encoding: "code_points"}) do
    text |> String.to_charlist() |> Enum.map_join(" ", &CodeUnits.format(&1, 2, 8))
  end

  @impl true
  def decode(text, %{encoding: encoding}) do
    CodeUnits.decode_lines(text, 2, fn tokens ->
      case encoding do
        "utf8" ->
          with values when is_list(values) <- CodeUnits.values(tokens, 2, 8),
               do: CodeUnits.utf8(values)

        "code_points" ->
          tokens |> CodeUnits.values(2, nil) |> CodeUnits.code_points()
      end
    end)
  end

  # UTF-8 bytes or code points: the one decoding everything first.
  @impl true
  def suggestions(input, _params) do
    if CodeUnits.all_numbers?(input, 2) do
      @encodings
      |> Enum.map(fn {label, encoding} ->
        {label, encoding, decode(input, %{encoding: encoding})}
      end)
      |> Enum.sort_by(fn {_, _, output} -> CodeUnits.rank(input, output) end, :desc)
      |> Enum.map(fn {label, encoding, output} ->
        %{
          label: label,
          params: %{encoding: encoding},
          reason:
            if(String.contains?(output, Alphabet.unknown()),
              do: "Some numbers aren't characters read this way.",
              else: "Every number reads as a character this way."
            )
        }
      end)
    else
      []
    end
  end

  @impl true
  def recognize(input) do
    with [best | _] <- suggestions(input, %{}),
         true <- CodeUnits.clean_decode?(input, decode(input, best.params)) do
      what = if best.params.encoding == "utf8", do: "UTF-8 bytes", else: "Unicode code points"
      "The text is only 0s and 1s, and they all decode as #{what}."
    else
      _ -> nil
    end
  end
end
