defmodule Subcipher.Steps.Ciphers.HexAscii do
  @moduledoc """
  Hexadecimal ASCII: each character written as its ASCII code in two
  hexadecimal digits, separated by spaces or run together. See
  `Subcipher.Steps.CodeUnits`.
  """
  use Subcipher.Steps.Cipher

  alias Subcipher.Steps.CodeUnits

  @impl true
  def type, do: "hex_ascii"

  @impl true
  def name, do: "Hexadecimal (ASCII)"

  @impl true
  def description,
    do: "Each character written as its ASCII code in two hexadecimal digits: H = 48."

  @impl true
  def fields, do: []

  @impl true
  # Characters outside ASCII become "?".
  def encode(text, _params) do
    text
    |> String.to_charlist()
    |> Enum.map_join(" ", fn c -> CodeUnits.format(if(c <= 127, do: c, else: ??), 16, 2) end)
  end

  @impl true
  def decode(text, _params) do
    CodeUnits.decode_lines(text, 16, fn tokens ->
      with values when is_list(values) <- CodeUnits.values(tokens, 16, 2),
           do: CodeUnits.ascii(values)
    end)
  end

  # Hexadecimal pairs that are all ASCII characters. (Words of the letters
  # A–F can't be: ASCII codes start with a digit 0–7.)
  @impl true
  def recognize(input) do
    if CodeUnits.all_numbers?(input, 16) and CodeUnits.clean_decode?(input, decode(input, %{})),
      do: "The text is only hexadecimal digits, and every pair is an ASCII character."
  end
end
