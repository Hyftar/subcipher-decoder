defmodule Subcipher.Algorithms.Algorithm do
  @moduledoc """
  Cipher steps with their settings, usable to encode and decode any text
  (see `Subcipher.Algorithms`). Made from a puzzle (a copy of its steps,
  `source_puzzle_id`) or from scratch, and editable.
  """
  use Ecto.Schema

  schema "algorithms" do
    field :title, :string
    # "pictures" (step 1 is the symbol key) or "text".
    field :input_kind, :string
    # [%{"type" => cipher type, "params" => params}] in order.
    field :steps, {:array, :map}, default: []
    # Pictures only: one entry per symbol with a letter:
    # %{"letter", "image" (index in images), "x", "y", "w", "h"}.
    field :symbol_key, {:array, :map}, default: []
    # Pictures only: %{"path", "width", "height", "glyph_height"}.
    field :images, {:array, :map}, default: []

    belongs_to :source_puzzle, Subcipher.Ciphers.Puzzle

    # Who owns it (set by the context, never cast), and whether everyone can
    # see it (read-only) or only its owner.
    belongs_to :user, Subcipher.Accounts.User
    field :public, :boolean, default: false

    timestamps(type: :utc_datetime)
  end

  def pictures?(%__MODULE__{input_kind: kind}), do: kind == "pictures"

  @doc "Whether `algorithm` is an unsaved draft (see `Subcipher.Algorithms.new_draft/2`)."
  def draft?(%__MODULE__{__meta__: %{state: state}}), do: state == :built
end
