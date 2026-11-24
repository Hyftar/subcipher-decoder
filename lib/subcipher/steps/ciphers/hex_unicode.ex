defmodule Subcipher.Steps.Ciphers.HexUnicode do
  @moduledoc """
  Hexadecimal Unicode: each character written in hexadecimal, either as its
  UTF-8 bytes (2 digits each, run together or not: ☀ = E2 98 80) or as its
  code point (one number per character, often written U+2600 or \\u2600).
  See `Subcipher.Steps.CodeUnits`.
  """
  use Subcipher.Steps.Cipher

  alias Subcipher.Steps.CodeUnits

  @encodings [{"UTF-8 bytes", "utf8"}, {"Code points", "code_points"}]

  @impl true
  def type, do: "hex_unicode"

  @impl true
  def name, do: "Hexadecimal (Unicode)"

  @impl true
  def description,
    do:
      "Each character written in hexadecimal: its UTF-8 bytes (E2 98 80) or its code point (U+2600)."

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
    for(<<byte <- text>>, do: CodeUnits.format(byte, 16, 2)) |> Enum.join(" ")
  end

  def encode(text, %{encoding: "code_points"}) do
    text |> String.to_charlist() |> Enum.map_join(" ", &("U+" <> CodeUnits.format(&1, 16, 4)))
  end

  @impl true
  def decode(text, %{encoding: encoding}) do
    CodeUnits.decode_lines(text, 16, fn tokens ->
      case encoding do
        "utf8" ->
          with values when is_list(values) <- CodeUnits.values(tokens, 16, 2),
               do: CodeUnits.utf8(values)

        "code_points" ->
          tokens |> CodeUnits.values(16, nil) |> CodeUnits.code_points()
      end
    end)
  end

  # UTF-8 bytes or code points: the one decoding everything first; U+ and
  # \u announce code points.
  @impl true
  def suggestions(input, _params) do
    if CodeUnits.all_numbers?(input, 16) do
      prefixed? = CodeUnits.code_point_prefix?(input)

      @encodings
      |> Enum.map(fn {label, encoding} ->
        {label, encoding, decode(input, %{encoding: encoding})}
      end)
      |> Enum.sort_by(
        fn {_, encoding, output} ->
          {prefixed? == (encoding == "code_points"), CodeUnits.rank(input, output)}
        end,
        :desc
      )
      |> Enum.map(fn {label, encoding, output} ->
        %{
          label: label,
          params: %{encoding: encoding},
          reason: reason(output, prefixed?, encoding)
        }
      end)
    else
      []
    end
  end

  defp reason(output, prefixed?, encoding) do
    valid =
      if String.contains?(output, Alphabet.unknown()),
        do: "Some numbers aren't characters read this way.",
        else: "Every number reads as a character this way."

    if prefixed? and encoding == "code_points",
      do: "The numbers are written U+… or \\u…, the notation of code points. " <> valid,
      else: valid
  end

  @impl true
  def recognize(input) do
    with [best | _] <- suggestions(input, %{}),
         true <- CodeUnits.clean_decode?(input, decode(input, best.params)) do
      what = if best.params.encoding == "utf8", do: "UTF-8 bytes", else: "Unicode code points"
      "The text is only hexadecimal numbers, and they all decode as #{what}."
    else
      _ -> nil
    end
  end
end
