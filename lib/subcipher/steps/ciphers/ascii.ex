defmodule Subcipher.Steps.Ciphers.Ascii do
  @moduledoc """
  ASCII codes: each character written as its ASCII code, in decimal
  (H = 72), hexadecimal (48) or binary (01001000, 8 bits or 7). Numbers are
  separated by spaces, or run together (then cut every 3 decimal digits, 2
  hexadecimal digits or `width` bits). See `Subcipher.Steps.CodeUnits`.
  """
  use Subcipher.Steps.Cipher

  alias Subcipher.Steps.CodeUnits

  @impl true
  def type, do: "ascii"

  @impl true
  def name, do: "ASCII codes"

  @impl true
  def description,
    do:
      "Each character written as its ASCII code: H = 72 (decimal), 48 (hex) or 01001000 (binary)."

  @impl true
  def fields do
    [
      %{
        name: :base,
        type: :select,
        label: "Numbers in",
        default: "10",
        options: CodeUnits.base_options()
      },
      %{
        name: :width,
        type: :select,
        label: "Bits per character",
        default: "8",
        options: [{"8 bits", "8"}, {"7 bits", "7"}],
        help:
          "Binary only: when the bits are run together (no spaces), how many make a character."
      }
    ]
  end

  @impl true
  # Characters outside ASCII become "?".
  def encode(text, %{base: base} = params) do
    base = CodeUnits.base(base)
    digits = digits(base, params)

    text
    |> String.to_charlist()
    |> Enum.map_join(" ", fn c ->
      CodeUnits.format(if(c <= 127, do: c, else: ??), base, digits)
    end)
  end

  @impl true
  def decode(text, %{base: base} = params) do
    base = CodeUnits.base(base)
    unit = unit(base, Map.put_new(params, :width, "8"))

    CodeUnits.decode_lines(text, base, fn tokens ->
      with values when is_list(values) <- CodeUnits.values(tokens, base, unit),
           do: CodeUnits.ascii(values)
    end)
  end

  # Digits written per character: decimal codes aren't padded.
  defp digits(2, %{width: width}), do: String.to_integer(width)
  defp digits(10, _params), do: 1
  defp digits(16, _params), do: 2

  # Digits per character when they are run together: decimal codes are then
  # padded to 3 digits (072105 = "Hi").
  defp unit(2, %{width: width}), do: String.to_integer(width)
  defp unit(base, _params), do: CodeUnits.byte_digits(base)

  # Every base the text is written in (and 8 or 7 bits a character, when
  # binary is run together), the one decoding everything first. Decimal
  # comes before hexadecimal on a tie: codes of only digits read more
  # naturally as decimal.
  @impl true
  def suggestions(input, _params) do
    input
    |> readings()
    |> Enum.map(fn params -> {params, decode(input, params)} end)
    |> Enum.sort_by(fn {_, output} -> CodeUnits.rank(input, output) end, :desc)
    |> Enum.map(fn {params, output} ->
      %{label: label(params), params: params, reason: reason(output)}
    end)
  end

  defp readings(input) do
    Enum.flat_map(CodeUnits.base_options(), fn {_, base} ->
      cond do
        not CodeUnits.all_numbers?(input, CodeUnits.base(base)) -> []
        base == "2" -> Enum.map(widths(input), &%{base: "2", width: &1})
        true -> [%{base: base}]
      end
    end)
  end

  defp label(%{base: "2", width: width}), do: "Binary, #{width} bits a character"
  defp label(%{base: "10"}), do: "Decimal"
  defp label(%{base: "16"}), do: "Hexadecimal"

  # 8 or 7 bits a character: only matters when they are run together.
  defp widths(input) do
    {:ok, tokens} = input |> String.replace("\n", " ") |> CodeUnits.tokens(2)
    if Enum.any?(tokens, &(byte_size(&1) > 8)), do: ["8", "7"], else: ["8"]
  end

  defp reason(output) do
    if String.contains?(output, Alphabet.unknown()),
      do: "Some numbers aren't ASCII characters read this way.",
      else: "Every number is an ASCII character read this way."
  end

  # Words of the letters A–F can't be hexadecimal ASCII: codes start with a
  # digit 0–7.
  @impl true
  def recognize(input) do
    with [best | _] <- suggestions(input, %{}),
         true <- CodeUnits.clean_decode?(input, decode(input, best.params)) do
      "The text is only #{what(best.params)}, and every one is an ASCII character."
    else
      _ -> nil
    end
  end

  defp what(%{base: "2", width: width}), do: "0s and 1s in groups of #{width} bits"
  defp what(%{base: "10"}), do: "decimal numbers"
  defp what(%{base: "16"}), do: "hexadecimal numbers"
end
