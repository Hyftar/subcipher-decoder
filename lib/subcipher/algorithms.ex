defmodule Subcipher.Algorithms do
  @moduledoc """
  Algorithms: ciphers usable on any text.

  An algorithm has steps (cipher types and settings), created from scratch
  (`create_algorithm/2`, a text algorithm) or copied from a puzzle
  (`create_from_puzzle/1`; later changes to either don't affect the other),
  and editable (`add_step/2`, `update_step_params/3`...; only ciphers that can
  encode). One made from a pictures puzzle also has its symbol key: a sample
  glyph for each letter, cropped from copies of the pictures. It can then

    * decode any cipher text, step 1 to the last (`decode/2`);
    * encode any plain text, the last step to step 1, with each cipher's
      `c:Subcipher.Steps.Cipher.encode/2` (`encode/2`); a pictures
      algorithm ends with the symbols of its key.

  Both return the trace of the text through the steps.

  A draft (`new_draft/2`) is an algorithm that isn't saved: a cipher to try
  without an account. It is edited like the others, its changes kept in
  memory, and can be saved as a puzzle (`save_as_puzzle/3`).
  """

  import Ecto.Query, warn: false

  alias Subcipher.{Ciphers, Repo, Steps}
  alias Subcipher.Accounts.Scope
  alias Subcipher.Algorithms.Algorithm
  alias Subcipher.Ciphers.Puzzle
  alias Subcipher.Steps.Step

  @doc "The algorithms of the scope's user, most recent first (none without a user)."
  def list_algorithms(nil), do: []

  def list_algorithms(%Scope{user: user}) do
    Repo.all(
      from a in Algorithm,
        where: a.user_id == ^user.id,
        order_by: [desc: a.inserted_at, desc: a.id]
    )
  end

  @doc "The public algorithms of other users, most recent first."
  def list_public_algorithms(scope) do
    query = from a in Algorithm, where: a.public, order_by: [desc: a.inserted_at, desc: a.id]

    case scope do
      %Scope{user: user} -> where(query, [a], a.user_id != ^user.id or is_nil(a.user_id))
      nil -> query
    end
    |> Repo.all()
  end

  @doc "The algorithm with `id` if the scope may see it (its own, or public), else `nil`."
  def get_algorithm_for(scope, id) do
    case get_algorithm(id) do
      nil -> nil
      algorithm -> if Scope.can_view?(scope, algorithm), do: algorithm
    end
  end

  @doc "Makes an algorithm public (everyone can use it, read-only) or private."
  def set_public(%Algorithm{} = algorithm, public) when is_boolean(public) do
    algorithm |> Ecto.Changeset.change(public: public) |> Repo.update()
  end

  def get_algorithm!(id), do: Repo.get!(Algorithm, id)

  @doc "The algorithm with `id` (an integer or a string from a URL), or `nil`."
  def get_algorithm(id) do
    case Ciphers.parse_id(id) do
      nil -> nil
      id -> Repo.get(Algorithm, id)
    end
  end

  ## Creating

  @doc """
  Why `puzzle` can't become an algorithm, as sentences for the user (`[]`
  when it can): steps whose cipher can't encode, or no symbol key yet.
  """
  def problems(%Puzzle{} = puzzle) do
    offset = if Puzzle.pictures?(puzzle), do: 1, else: 0

    steps =
      for {step, i} <- Enum.with_index(puzzle.steps, 1 + offset),
          cipher = Steps.cipher!(step.type),
          not Steps.implements?(cipher, :encode, 2),
          do:
            "Step #{i} (#{cipher.name()}) can't be reversed: its settings only fit this puzzle's text."

    letters =
      if Puzzle.pictures?(puzzle) and symbol_key_entries(puzzle) == [],
        do: ["No symbol has a letter yet: the symbol key is empty."],
        else: []

    letters ++ steps
  end

  @doc """
  Creates an algorithm from `puzzle`, owned by the scope's user. Returns `{:ok, algorithm}` or
  `{:error, problems}` (see `problems/1`).
  """
  def create_from_puzzle(%Scope{user: user}, %Puzzle{} = puzzle) do
    puzzle = Ciphers.get_puzzle!(puzzle.id)

    case problems(puzzle) do
      [] ->
        {symbol_key, images} = build_symbol_key(puzzle)

        %Algorithm{
          title: puzzle.title,
          input_kind: puzzle.input_kind,
          source_puzzle_id: puzzle.id,
          user_id: user.id,
          steps: Enum.map(puzzle.steps, &%{"type" => &1.type, "params" => &1.params}),
          symbol_key: symbol_key,
          images: images
        }
        |> Repo.insert()

      problems ->
        {:error, problems}
    end
  end

  @doc "The ciphers an algorithm can use: those that can encode."
  def ciphers, do: Enum.filter(Steps.ciphers(), &Steps.implements?(&1, :encode, 2))

  @doc """
  Creates a text algorithm from scratch, starting with one step of cipher
  `type` (default settings), not attached to any puzzle, owned by the scope's
  user.
  """
  def create_algorithm(%Scope{user: user}, type, title \\ "New algorithm") do
    with {:ok, step} <- new_step(type) do
      Repo.insert(%Algorithm{user_id: user.id, title: title, input_kind: "text", steps: [step]})
    end
  end

  @doc """
  An unsaved text algorithm (a draft) with one step of cipher `type`, its
  settings taken from `params` when they are valid (else the defaults).
  Returns `{:ok, draft}`, or `{:error, :unknown_cipher}`.
  """
  def new_draft(type, params \\ %{}) do
    with {:ok, step} <- new_step(type) do
      draft = %Algorithm{
        title: Steps.cipher!(type).name(),
        input_kind: "text",
        steps: [step]
      }

      case update_step_params(draft, 0, params) do
        {:ok, draft} -> {:ok, draft}
        {:error, _} -> {:ok, draft}
      end
    end
  end

  @doc """
  Saves `draft`'s steps as a text puzzle of the scope's user, decoding
  `attrs`' input_text (with its title). See `Ciphers.create_text_puzzle_with_steps/3`.
  """
  def save_as_puzzle(%Scope{} = scope, %Algorithm{} = draft, attrs) do
    Ciphers.create_text_puzzle_with_steps(scope, attrs, draft.steps)
  end

  ## Editing (the steps are numbered from 0 here, in decoding order)

  def rename(%Algorithm{} = algorithm, title) do
    case String.trim(title || "") do
      "" -> {:error, :blank}
      title -> update_steps(algorithm, algorithm.steps, title: String.slice(title, 0, 120))
    end
  end

  @doc "Appends a step of cipher `type`, with default settings."
  def add_step(%Algorithm{} = algorithm, type) do
    with {:ok, step} <- new_step(type) do
      update_steps(algorithm, algorithm.steps ++ [step])
    end
  end

  @doc "Changes the cipher of step `index`; its settings are reset."
  def change_step_type(%Algorithm{} = algorithm, index, type) do
    with {:ok, step} <- new_step(type),
         true <- index in 0..(length(algorithm.steps) - 1)//1 || {:error, :not_found} do
      update_steps(algorithm, List.replace_at(algorithm.steps, index, step))
    end
  end

  @doc """
  Updates some of the settings of step `index` (the others are kept).
  Returns `{:error, changeset}` when they are invalid.
  """
  def update_step_params(%Algorithm{} = algorithm, index, params) do
    case Enum.at(algorithm.steps, index) do
      nil ->
        {:error, :not_found}

      %{"type" => type, "params" => current} = step ->
        params = Map.new(params, fn {k, v} -> {to_string(k), v} end)
        changeset = Steps.params_changeset(type, Map.merge(current, params))

        if changeset.valid? do
          params =
            changeset
            |> Ecto.Changeset.apply_changes()
            |> Map.new(fn {k, v} -> {to_string(k), v} end)

          update_steps(
            algorithm,
            List.replace_at(algorithm.steps, index, %{step | "params" => params})
          )
        else
          {:error, %{changeset | action: :validate}}
        end
    end
  end

  @doc "Removes step `index`. A text algorithm keeps at least one step."
  def delete_step(%Algorithm{} = algorithm, index) do
    cond do
      index not in 0..(length(algorithm.steps) - 1)//1 -> {:error, :not_found}
      length(algorithm.steps) == 1 and not Algorithm.pictures?(algorithm) -> {:error, :last_step}
      true -> update_steps(algorithm, List.delete_at(algorithm.steps, index))
    end
  end

  @doc "Moves step `index` one place earlier (`:up`) or later (`:down`)."
  def move_step(%Algorithm{} = algorithm, index, direction) when direction in [:up, :down] do
    target = if direction == :up, do: index - 1, else: index + 1
    steps = algorithm.steps

    if index in 0..(length(steps) - 1)//1 and target in 0..(length(steps) - 1)//1 do
      steps =
        steps
        |> List.replace_at(index, Enum.at(steps, target))
        |> List.replace_at(target, Enum.at(steps, index))

      update_steps(algorithm, steps)
    else
      {:ok, algorithm}
    end
  end

  defp new_step(type) do
    with {:ok, cipher} <- Steps.fetch_cipher(type),
         true <- cipher in ciphers() || {:error, :not_reversible} do
      params =
        cipher.fields()
        |> Map.new(&{to_string(&1.name), &1.default})

      {:ok, %{"type" => cipher.type(), "params" => params}}
    else
      :error -> {:error, :unknown_cipher}
      error -> error
    end
  end

  # A draft isn't saved: its changes are only applied.
  defp update_steps(algorithm, steps, changes \\ []) do
    changeset = Ecto.Changeset.change(algorithm, [steps: steps] ++ changes)

    if Algorithm.draft?(algorithm),
      do: {:ok, Ecto.Changeset.apply_changes(changeset)},
      else: Repo.update(changeset)
  end

  def delete_algorithm(%Algorithm{} = algorithm) do
    with {:ok, algorithm} <- Repo.delete(algorithm) do
      for %{"path" => path} <- algorithm.images do
        File.rm(Path.join(Ciphers.uploads_dir(), Path.basename(path)))
      end

      {:ok, algorithm}
    end
  end

  # The symbols with a letter, most frequent first, each with its sample
  # glyph (`Ciphers.sample_glyph/2`).
  defp symbol_key_entries(puzzle) do
    by_symbol = Enum.group_by(puzzle.glyphs, & &1.symbol_id)

    puzzle.symbols
    |> Enum.filter(&(not &1.ignored and is_binary(&1.letter) and &1.letter != ""))
    |> Enum.filter(&Map.has_key?(by_symbol, &1.id))
    |> Enum.sort_by(&{-length(by_symbol[&1.id]), &1.id})
    |> Enum.map(&{&1, Ciphers.sample_glyph(&1, by_symbol[&1.id])})
  end

  # The key's entries, and copies of the pictures their glyphs come from (so
  # the algorithm works even if the puzzle is deleted).
  defp build_symbol_key(%Puzzle{} = puzzle) do
    if Puzzle.pictures?(puzzle) do
      entries = symbol_key_entries(puzzle)
      used = entries |> Enum.map(fn {_, glyph} -> glyph.image_id end) |> Enum.uniq()
      images = Enum.filter(puzzle.images, &(&1.id in used))
      index = images |> Enum.with_index() |> Map.new(fn {image, i} -> {image.id, i} end)

      key =
        Enum.map(entries, fn {symbol, glyph} ->
          %{
            "letter" => symbol.letter,
            "image" => index[glyph.image_id],
            "x" => glyph.x,
            "y" => glyph.y,
            "w" => glyph.w,
            "h" => glyph.h
          }
        end)

      {key, Enum.map(images, &copy_image(&1, puzzle))}
    else
      {[], []}
    end
  end

  defp copy_image(image, puzzle) do
    source = Path.join(Ciphers.uploads_dir(), Path.basename(image.path))
    filename = "#{Ecto.UUID.generate()}#{Path.extname(image.path)}"
    File.cp!(source, Path.join(Ciphers.uploads_dir(), filename))

    heights = for g <- puzzle.glyphs, g.image_id == image.id, do: g.h
    median = heights |> Enum.sort() |> Enum.at(div(length(heights), 2))

    %{
      "path" => "/uploads/#{filename}",
      "width" => image.width,
      "height" => image.height,
      "glyph_height" => median
    }
  end

  ## Running

  @typedoc """
  A stage of the trace: `:text` with a string value, or `:symbols` with a
  list of `{:symbol, key_index} | {:char, string} | {:missing, letter}`.
  """
  @type stage :: %{label: String.t(), kind: :text | :symbols, value: term()}

  @doc """
  Decodes `input` through the steps, in order. For a pictures algorithm,
  `input` is a list of symbol tokens (see `t:stage/0`); otherwise text.
  Returns the stages, from the input to the decoded text.
  """
  def decode(%Algorithm{} = algorithm, input) do
    {first, text} =
      if Algorithm.pictures?(algorithm) do
        letters = symbols_to_text(algorithm, input)

        {[
           %{label: "Symbols", kind: :symbols, value: input},
           %{label: "Step 1 · Symbol substitution", kind: :text, value: letters}
         ], letters}
      else
        {[%{label: "Cipher text", kind: :text, value: input}], input}
      end

    {stages, _} =
      algorithm
      |> steps()
      |> Enum.map_reduce(text, fn {number, cipher, params}, text ->
        out = cipher.decode(text, params)
        {%{label: "Step #{number} · #{cipher.name()}", kind: :text, value: out}, out}
      end)

    first ++ stages
  end

  @doc """
  Encodes plain `text` through the steps, the last one first. Returns the
  stages, from the plain text to the cipher text (symbols for a pictures
  algorithm).
  """
  def encode(%Algorithm{} = algorithm, text) do
    {stages, encoded} =
      algorithm
      |> steps()
      |> Enum.reverse()
      |> Enum.map_reduce(text, fn {number, cipher, params}, text ->
        out = cipher.encode(text, params)
        {%{label: "Step #{number} · #{cipher.name()}", kind: :text, value: out}, out}
      end)

    last =
      if Algorithm.pictures?(algorithm),
        do: [
          %{
            label: "Step 1 · Symbol substitution",
            kind: :symbols,
            value: text_to_symbols(algorithm, encoded)
          }
        ],
        else: []

    [%{label: "Plain text", kind: :text, value: text} | stages] ++ last
  end

  # The steps as {number, cipher, params}; numbered after the symbols (step
  # 1) for a pictures algorithm.
  defp steps(algorithm) do
    offset = if Algorithm.pictures?(algorithm), do: 2, else: 1

    algorithm.steps
    |> Enum.with_index(offset)
    |> Enum.map(fn {%{"type" => type, "params" => params}, number} ->
      {number, Steps.cipher!(type), Steps.params(%Step{type: type, params: params})}
    end)
  end

  @doc "Letters of symbol tokens (unknown symbols as \"·\")."
  def symbols_to_text(%Algorithm{symbol_key: key}, tokens) do
    Enum.map_join(tokens, fn
      {:symbol, i} -> (Enum.at(key, i) || %{})["letter"] || Steps.Alphabet.unknown()
      {:char, char} -> char
      {:missing, _letter} -> Steps.Alphabet.unknown()
    end)
  end

  @doc """
  The symbols writing `text`, longest letter groups first ("TH" before "T");
  letters no symbol stands for are `{:missing, letter}`, anything else is
  kept as `{:char, char}`.
  """
  def text_to_symbols(%Algorithm{symbol_key: key}, text) do
    # The first (most frequent) symbol of each letter group.
    inverse =
      key
      |> Enum.with_index()
      |> Enum.reverse()
      |> Map.new(fn {%{"letter" => letter}, i} -> {String.upcase(letter), i} end)

    lengths =
      inverse |> Map.keys() |> Enum.map(&String.length/1) |> Enum.uniq() |> Enum.sort(:desc)

    to_symbols(String.upcase(text), inverse, lengths, [])
  end

  defp to_symbols("", _inverse, _lengths, acc), do: Enum.reverse(acc)

  defp to_symbols(text, inverse, lengths, acc) do
    found =
      Enum.find_value(lengths, fn length ->
        {head, rest} = String.split_at(text, length)
        if Map.has_key?(inverse, head), do: {inverse[head], rest}
      end)

    case found do
      {i, rest} ->
        to_symbols(rest, inverse, lengths, [{:symbol, i} | acc])

      nil ->
        {char, rest} = String.split_at(text, 1)
        token = if char =~ ~r/^[A-Z]$/, do: {:missing, char}, else: {:char, char}
        to_symbols(rest, inverse, lengths, [token | acc])
    end
  end
end
