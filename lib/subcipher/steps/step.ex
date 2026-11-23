defmodule Subcipher.Steps.Step do
  @moduledoc """
  A decoding step after the pictures: a text cipher (`type`, see
  `Subcipher.Steps.ciphers/0`) with its parameters, applied to the previous
  step's output.
  """
  use Ecto.Schema

  schema "steps" do
    field :position, :integer
    field :type, :string
    # Validated by the cipher's fields (Subcipher.Steps.params_changeset/2).
    field :params, :map, default: %{}

    belongs_to :puzzle, Subcipher.Ciphers.Puzzle

    timestamps(type: :utc_datetime)
  end
end
