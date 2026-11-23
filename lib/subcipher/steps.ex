defmodule Subcipher.Steps do
  @moduledoc """
  Decoding pipeline of a puzzle.

  Step 1 is always the pictures: symbols substituted with letters (see
  `Subcipher.Ciphers.plaintext/1`). Each following step is a text cipher
  (`Subcipher.Steps.Cipher`) that decodes the previous step's output.
  """

  import Ecto.Query, warn: false

  alias Ecto.Changeset
  alias Subcipher.Repo
  alias Subcipher.Ciphers.Puzzle
  alias Subcipher.Steps.Step

  alias Subcipher.Steps.Ciphers.{
    Caesar,
    KeywordSubstitution,
    LetterSubstitution,
    SymbolSubstitution
  }

  # Available cipher types, in the order offered to the user. To add one,
  # implement Subcipher.Steps.Cipher and list it here.
  @ciphers [SymbolSubstitution, LetterSubstitution, Caesar, KeywordSubstitution]

  def ciphers, do: @ciphers

  def fetch_cipher(type) do
    case Enum.find(@ciphers, &(&1.type() == type)) do
      nil -> :error
      cipher -> {:ok, cipher}
    end
  end

  def cipher!(type) do
    case fetch_cipher(type) do
      {:ok, cipher} -> cipher
      :error -> raise ArgumentError, "unknown cipher type #{inspect(type)}"
    end
  end

  @doc """
  Whether `cipher` implements an optional callback (`summary/1`,
  `candidates/2`). Loads the module first: `function_exported?/3` alone is
  false for modules not loaded yet.
  """
  def implements?(cipher, fun, arity) do
    Code.ensure_loaded?(cipher) and function_exported?(cipher, fun, arity)
  end

  ## Parameters

  @doc """
  Changeset casting and validating `params` for a cipher `type`, built from
  the cipher's `fields/0` and `validate/1`.
  """
  def params_changeset(type, params) do
    cipher = cipher!(type)
    fields = cipher.fields()
    defaults = Map.new(fields, &{&1.name, &1.default})
    types = Map.new(fields, &{&1.name, ecto_type(&1.type)})

    # Emptied number inputs cast to nil: numbers are always required.
    required = for %{type: :integer, name: name} <- fields, do: name

    {defaults, types}
    |> Changeset.cast(params || %{}, Map.keys(types))
    |> Changeset.validate_required(required)
    |> cipher.validate()
  end

  defp ecto_type(:integer), do: :integer
  defp ecto_type(:string), do: :string
  defp ecto_type(:letter_map), do: {:map, :string}
  defp ecto_type(:symbol_map), do: {:map, :string}

  @doc "The parameters of a step, with atom keys and defaults applied."
  def params(%Step{type: type, params: params}) do
    type |> params_changeset(params) |> Changeset.apply_changes()
  end

  defp stringify_keys(map), do: Map.new(map, fn {k, v} -> {to_string(k), v} end)

  ## Running

  @doc """
  The text the stored steps start from: the symbols of the pictures
  substituted with their letters (the implicit step 1 of a pictures
  puzzle), or the puzzle's input text.
  """
  def source(%Puzzle{} = puzzle) do
    if Puzzle.pictures?(puzzle),
      do: Subcipher.Ciphers.plaintext(puzzle),
      else: puzzle.input_text
  end

  @doc """
  Runs `steps` in order on `input` (step 1's output). Returns one entry per
  step: `%{step: step, cipher: module, params: map, input: text, output: text}`.
  """
  def run(input, steps) do
    {results, _} =
      Enum.map_reduce(steps, input, fn step, input ->
        cipher = cipher!(step.type)
        params = params(step)
        output = cipher.decode(input, params)
        {%{step: step, cipher: cipher, params: params, input: input, output: output}, output}
      end)

    results
  end

  ## Managing steps

  def list_steps(%Puzzle{id: id}) do
    Repo.all(from s in Step, where: s.puzzle_id == ^id, order_by: s.position)
  end

  @doc "Appends a step of cipher `type`, with default parameters."
  def add_step(%Puzzle{id: puzzle_id}, type) do
    with {:ok, cipher} <- fetch_cipher(type) do
      position =
        Repo.one(from s in Step, where: s.puzzle_id == ^puzzle_id, select: max(s.position)) || 0

      Repo.insert(%Step{
        puzzle_id: puzzle_id,
        position: position + 1,
        type: cipher.type(),
        params: default_params(cipher)
      })
    else
      :error -> {:error, :unknown_cipher}
    end
  end

  @doc """
  Updates a step's parameters. Returns `{:error, changeset}` (from
  `params_changeset/2`) when they are invalid.
  """
  def update_params(%Step{} = step, params) do
    changeset = params_changeset(step.type, params)

    if changeset.valid? do
      params = changeset |> Changeset.apply_changes() |> stringify_keys()
      step |> Changeset.change(params: params) |> Repo.update()
    else
      {:error, %{changeset | action: :validate}}
    end
  end

  @doc """
  Removes a step. A text puzzle keeps at least one step (its input can only
  be decoded by steps): `{:error, :last_step}`.
  """
  def delete_step(%Step{} = step) do
    puzzle = Repo.get!(Puzzle, step.puzzle_id)
    count = Repo.aggregate(from(s in Step, where: s.puzzle_id == ^puzzle.id), :count)

    if count <= 1 and not Puzzle.pictures?(puzzle),
      do: {:error, :last_step},
      else: Repo.delete(step)
  end

  @doc "Changes the cipher of a step; its parameters are reset to the defaults."
  def change_type(%Step{} = step, type) do
    with {:ok, cipher} <- fetch_cipher(type) do
      step
      |> Changeset.change(type: cipher.type(), params: default_params(cipher))
      |> Repo.update()
    else
      :error -> {:error, :unknown_cipher}
    end
  end

  defp default_params(cipher),
    do: cipher.fields() |> Map.new(&{&1.name, &1.default}) |> stringify_keys()

  @doc "Moves a step one place earlier (`:up`) or later (`:down`)."
  def move_step(%Step{} = step, direction) when direction in [:up, :down] do
    steps = list_steps(%Puzzle{id: step.puzzle_id})
    ids = Enum.map(steps, & &1.id)
    index = Enum.find_index(ids, &(&1 == step.id))
    target = if direction == :up, do: index - 1, else: index + 1

    if target < 0 or target >= length(ids) do
      {:ok, steps}
    else
      ids =
        ids |> List.replace_at(index, Enum.at(ids, target)) |> List.replace_at(target, step.id)

      Repo.transaction(fn ->
        # Positions are unique per puzzle: park on temporary negative
        # positions first.
        for {id, i} <- Enum.with_index(ids, 1) do
          Repo.update_all(from(s in Step, where: s.id == ^id), set: [position: -i])
        end

        for {id, i} <- Enum.with_index(ids, 1) do
          Repo.update_all(from(s in Step, where: s.id == ^id), set: [position: i])
        end

        list_steps(%Puzzle{id: step.puzzle_id})
      end)
    end
  end
end
