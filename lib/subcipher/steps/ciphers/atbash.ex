defmodule Subcipher.Steps.Ciphers.Atbash do
  @moduledoc "Atbash: the alphabet reversed (A ↔ Z, B ↔ Y…). Decoding is the same operation."
  use Subcipher.Steps.Cipher

  @impl true
  def type, do: "atbash"

  @impl true
  def name, do: "Atbash"

  @impl true
  def description, do: "The alphabet is reversed: A ↔ Z, B ↔ Y, C ↔ X…"

  @impl true
  def osrs_usage, do: "Demonic Pacts League reveal."

  @impl true
  def fields, do: []

  @impl true
  def decode(text, _params), do: Alphabet.map_letters(text, &(25 - &1))

  # Its own reverse.
  @impl true
  def encode(text, params), do: decode(text, params)
end
