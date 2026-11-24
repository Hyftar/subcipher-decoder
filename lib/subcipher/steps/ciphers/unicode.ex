defmodule Subcipher.Steps.Ciphers.Unicode do
  @moduledoc """
  Unicode: each character written in decimal, hexadecimal or binary, either
  as its UTF-8 bytes (☀ = E2 98 80; run together or not, a byte is 3
  decimal digits, 2 hexadecimal digits or 8 bits) or as its code point (one
  number per character: ☀ = 9728, U+2600 or \\u2600, 10011000000000). See
  `Subcipher.Steps.CodeUnits`.
  """
  use Subcipher.Steps.Cipher

  alias Subcipher.Steps.CodeUnits

  @encodings [{"UTF-8 bytes", "utf8"}, {"Code points", "code_points"}]

  @impl true
  def type, do: "unicode"

  @impl true
  def name, do: "Unicode"

  @impl true
  def description,
    do:
      "Each character written as its UTF-8 bytes (☀ = E2 98 80) or its code point (U+2600), in decimal, hex or binary."

  @impl true
  def fields do
    [
      %{
        name: :base,
        type: :select,
        label: "Numbers in",
        default: "16",
        options: CodeUnits.base_options()
      },
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
  def encode(text, %{base: base, encoding: "utf8"}) do
    base = CodeUnits.base(base)
    digits = if base == 10, do: 1, else: CodeUnits.byte_digits(base)
    for(<<byte <- text>>, do: CodeUnits.format(byte, base, digits)) |> Enum.join(" ")
  end

  def encode(text, %{base: base, encoding: "code_points"}) do
    text |> String.to_charlist() |> Enum.map_join(" ", &code_point(&1, CodeUnits.base(base)))
  end

  defp code_point(c, 16), do: "U+" <> CodeUnits.format(c, 16, 4)
  defp code_point(c, 10), do: Integer.to_string(c)
  defp code_point(c, 2), do: CodeUnits.format(c, 2, 8)

  @impl true
  def decode(text, %{base: base, encoding: encoding}) do
    base = CodeUnits.base(base)

    CodeUnits.decode_lines(text, base, fn tokens ->
      case encoding do
        "utf8" ->
          with values when is_list(values) <-
                 CodeUnits.values(tokens, base, CodeUnits.byte_digits(base)),
               do: CodeUnits.utf8(values)

        "code_points" ->
          tokens |> CodeUnits.values(base, nil) |> CodeUnits.code_points()
      end
    end)
  end

  # Every base the text is written in, as UTF-8 bytes or code points: the
  # reading decoding everything first; U+ and \u announce code points.
  # Decimal comes before hexadecimal on a tie: numbers of only digits read
  # more naturally as decimal.
  @impl true
  def suggestions(input, _params) do
    prefixed? = CodeUnits.code_point_prefix?(input)

    for {_, base} <- CodeUnits.base_options(),
        CodeUnits.all_numbers?(input, CodeUnits.base(base)),
        {_, encoding} <- @encodings do
      params = %{base: base, encoding: encoding}
      {params, decode(input, params)}
    end
    |> Enum.sort_by(
      fn {params, output} ->
        {prefixed? and params.encoding == "code_points", CodeUnits.rank(input, output)}
      end,
      :desc
    )
    |> Enum.map(fn {params, output} ->
      %{label: label(params), params: params, reason: reason(output, prefixed?, params)}
    end)
  end

  defp label(%{base: base, encoding: encoding}) do
    {what, _} = List.keyfind(@encodings, encoding, 1)
    base_name = base |> CodeUnits.base() |> CodeUnits.base_name()
    "#{what}, #{base_name}"
  end

  defp reason(output, prefixed?, params) do
    valid =
      if String.contains?(output, Alphabet.unknown()),
        do: "Some numbers aren't characters read this way.",
        else: "Every number reads as a character this way."

    if prefixed? and params.encoding == "code_points",
      do: "The numbers are written U+… or \\u…, the notation of code points. " <> valid,
      else: valid
  end

  # Any hexadecimal word (or list of numbers) is valid code points: without
  # a prefix announcing them, code points must decode to some ASCII letters
  # or spaces ("aaa bbb" isn't "઼ ௻").
  @impl true
  def recognize(input) do
    with [best | _] <- suggestions(input, %{}),
         output = decode(input, best.params),
         true <- CodeUnits.clean_decode?(input, output),
         true <-
           best.params.encoding == "utf8" or CodeUnits.code_point_prefix?(input) or
             output =~ ~r/[A-Za-z ]/ do
      numbers =
        case best.params.base do
          "2" -> "0s and 1s"
          base -> "#{base |> CodeUnits.base() |> CodeUnits.base_name()} numbers"
        end

      what =
        if best.params.encoding == "utf8", do: "UTF-8 bytes", else: "Unicode code points"

      "The text is only #{numbers}, and they all decode as #{what}."
    else
      _ -> nil
    end
  end
end
