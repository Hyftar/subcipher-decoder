defmodule Subcipher.Ciphers.Puzzle do
  use Ecto.Schema
  import Ecto.Changeset

  @input_kinds ~w(pictures text)

  schema "puzzles" do
    field :title, :string
    field :threshold, :float
    # "pictures": step 1 substitutes the symbols detected in the pictures.
    # "text": the cipher text is `input_text`, decoded by the steps only.
    field :input_kind, :string, default: "pictures"
    field :input_text, :string, default: ""

    has_many :images, Subcipher.Ciphers.Image
    has_many :symbols, Subcipher.Ciphers.Symbol
    has_many :glyphs, Subcipher.Ciphers.Glyph
    has_many :steps, Subcipher.Steps.Step

    # Who owns it (set by the context, never cast), and whether everyone can
    # see it (read-only) or only its owner.
    belongs_to :user, Subcipher.Accounts.User
    field :public, :boolean, default: false

    timestamps(type: :utc_datetime)
  end

  def pictures?(%__MODULE__{input_kind: kind}), do: kind == "pictures"

  def changeset(puzzle, attrs) do
    puzzle
    |> cast(attrs, [:title, :threshold])
    |> update_change(:title, &String.trim/1)
    |> validate_required([:title, :threshold])
    |> validate_length(:title, max: 120)
  end

  @doc "Changeset of a puzzle whose input is text."
  def text_changeset(puzzle, attrs) do
    puzzle
    |> cast(attrs, [:title, :input_text, :threshold])
    |> update_change(:title, &String.trim/1)
    |> put_change(:input_kind, "text")
    |> validate_required([:title, :input_text, :threshold])
    |> validate_length(:title, max: 120)
    |> validate_length(:input_text, max: 100_000)
    |> validate_inclusion(:input_kind, @input_kinds)
  end

  def input_text_changeset(puzzle, attrs) do
    puzzle
    |> cast(attrs, [:input_text], empty_values: [nil])
    |> validate_length(:input_text, max: 100_000)
  end

  def title_changeset(puzzle, attrs) do
    puzzle
    |> cast(attrs, [:title])
    |> update_change(:title, &String.trim/1)
    |> validate_required([:title])
    |> validate_length(:title, max: 120)
  end
end
