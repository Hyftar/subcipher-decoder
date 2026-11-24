defmodule Subcipher.Steps.Ciphers.BinaryAscii do
  @moduledoc """
  Binary ASCII: each character written as its ASCII code in binary, 8 bits
  (or 7). Groups are separated by spaces, or run together (then cut every
  `width` bits). See `Subcipher.Steps.CodeUnits`.
  """
  use Subcipher.Steps.Cipher

  alias Subcipher.Steps.CodeUnits

  @impl true
  def type, do: "binary_ascii"

  @impl true
  def name, do: "Binary (ASCII)"

  @impl true
  def description,
    do: "Each character written as its ASCII code in binary, 8 bits: H = 01001000."

  @impl true
  def fields do
    [
      %{
        name: :width,
        type: :select,
        label: "Bits per character",
        default: "8",
        options: [{"8 bits", "8"}, {"7 bits", "7"}],
        help: "When the bits are run together (no spaces), how many make a character."
      }
    ]
  end

  @impl true
  # Characters outside ASCII become "?".
  def encode(text, %{width: width}) do
    width = String.to_integer(width)

    text
    |> String.to_charlist()
    |> Enum.map_join(" ", fn c -> CodeUnits.format(if(c <= 127, do: c, else: ??), 2, width) end)
  end

  @impl true
  def decode(text, %{width: width}) do
    width = String.to_integer(width)

    CodeUnits.decode_lines(text, 2, fn tokens ->
      with values when is_list(values) <- CodeUnits.values(tokens, 2, width),
           do: CodeUnits.ascii(values)
    end)
  end

  # 8 or 7 bits a character: only matters when they are run together.
  @impl true
  def suggestions(input, _params) do
    with true <- CodeUnits.all_numbers?(input, 2),
         {:ok, tokens} <- input |> String.replace("\n", " ") |> CodeUnits.tokens(2) do
      widths = if Enum.any?(tokens, &(byte_size(&1) > 8)), do: ["8", "7"], else: ["8"]

      widths
      |> Enum.map(fn width -> {width, decode(input, %{width: width})} end)
      |> Enum.sort_by(fn {_, output} -> CodeUnits.rank(input, output) end, :desc)
      |> Enum.map(fn {width, output} ->
        %{
          label: "#{width} bits a character",
          params: %{width: width},
          reason: reason(output)
        }
      end)
    else
      _ -> []
    end
  end

  defp reason(output) do
    if String.contains?(output, Alphabet.unknown()),
      do: "Some groups aren't ASCII characters read this way.",
      else: "Every group of bits is an ASCII character read this way."
  end

  @impl true
  def recognize(input) do
    with [best | _] <- suggestions(input, %{}),
         true <- CodeUnits.clean_decode?(input, decode(input, best.params)) do
      "The text is only 0s and 1s, and every group of #{best.params.width} bits is an ASCII character."
    else
      _ -> nil
    end
  end
end
