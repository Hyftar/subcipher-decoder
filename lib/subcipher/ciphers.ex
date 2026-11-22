defmodule Subcipher.Ciphers do
  @moduledoc """
  Cipher puzzles: a picture, the glyphs detected in it, grouped into symbols
  that the user substitutes with letters.
  """

  import Ecto.Query, warn: false

  alias Ecto.Multi
  alias Subcipher.Repo
  alias Subcipher.Ciphers.{Analysis, Glyph, Puzzle, Symbol}

  def default_threshold, do: Analysis.default_threshold()

  ## Puzzles

  @doc "Lists puzzles, most recent first, with glyph and symbol counts."
  def list_puzzles do
    glyphs = from g in Glyph, group_by: g.puzzle_id, select: %{puzzle_id: g.puzzle_id, n: count()}

    symbols =
      from s in Symbol,
        where: not s.ignored,
        group_by: s.puzzle_id,
        select: %{
          puzzle_id: s.puzzle_id,
          n: count(),
          solved: filter(count(), not is_nil(s.letter))
        }

    Repo.all(
      from p in Puzzle,
        left_join: g in subquery(glyphs),
        on: g.puzzle_id == p.id,
        left_join: s in subquery(symbols),
        on: s.puzzle_id == p.id,
        order_by: [desc: p.inserted_at, desc: p.id],
        select: %{
          puzzle: p,
          glyph_count: coalesce(g.n, 0),
          symbol_count: coalesce(s.n, 0),
          solved_count: coalesce(s.solved, 0)
        }
    )
  end

  @doc "Gets a puzzle with its symbols and glyphs (in reading order)."
  def get_puzzle!(id) do
    Puzzle
    |> Repo.get!(id)
    |> Repo.preload(
      symbols: from(s in Symbol, order_by: s.id),
      glyphs: from(g in Glyph, order_by: g.position)
    )
  end

  @doc """
  Creates a puzzle from an uploaded picture and the glyphs the browser
  detected in it (see `Analysis.parse_detection/1`).

  `image` is `%{path: tmp_path, ext: ".png", width: w, height: h}`; the file
  is copied to the uploads directory.
  """
  def create_puzzle(attrs, image, glyphs, opts \\ []) do
    threshold = Keyword.get(opts, :threshold, default_threshold())
    filename = "#{Ecto.UUID.generate()}#{image.ext}"
    dest = Path.join(uploads_dir(), filename)

    changeset =
      Puzzle.changeset(
        %Puzzle{},
        Map.merge(stringify(attrs), %{
          "image_path" => "/uploads/#{filename}",
          "image_width" => image.width,
          "image_height" => image.height,
          "threshold" => threshold
        })
      )

    with {:ok, _} <- validate(changeset),
         :ok <- File.mkdir_p(uploads_dir()),
         :ok <- File.cp(image.path, dest) do
      analyzed = Analysis.analyze(glyphs, threshold: threshold)

      Multi.new()
      |> Multi.insert(:puzzle, changeset)
      |> Multi.run(:glyphs, fn repo, %{puzzle: puzzle} ->
        insert_symbols_and_glyphs(repo, puzzle, analyzed, fn _cluster -> %{} end)
      end)
      |> Repo.transaction()
      |> case do
        {:ok, %{puzzle: puzzle}} ->
          {:ok, get_puzzle!(puzzle.id)}

        {:error, _step, reason, _} ->
          File.rm(dest)
          {:error, reason}
      end
    end
  end

  defp validate(%Ecto.Changeset{valid?: true} = cs), do: {:ok, cs}
  defp validate(cs), do: {:error, %{cs | action: :insert}}

  defp stringify(attrs), do: Map.new(attrs, fn {k, v} -> {to_string(k), v} end)

  # `analyzed` glyphs carry a `:cluster` index; one symbol is created per
  # cluster. `symbol_attrs.(cluster)` returns extra attrs for that symbol.
  defp insert_symbols_and_glyphs(repo, puzzle, analyzed, symbol_attrs) do
    now = DateTime.utc_now(:second)
    clusters = analyzed |> Enum.map(& &1.cluster) |> Enum.uniq() |> Enum.sort()

    {_, symbol_ids} =
      repo.insert_all(
        Symbol,
        Enum.map(clusters, fn c ->
          Map.merge(
            %{puzzle_id: puzzle.id, ignored: false, inserted_at: now, updated_at: now},
            symbol_attrs.(c)
          )
        end),
        returning: [:id]
      )

    # insert_all returns rows in insertion order, i.e. cluster order.
    id_by_cluster = clusters |> Enum.zip(Enum.map(symbol_ids, & &1.id)) |> Map.new()

    rows =
      Enum.map(analyzed, fn g ->
        %{
          puzzle_id: puzzle.id,
          symbol_id: Map.fetch!(id_by_cluster, g.cluster),
          position: g.position,
          line: g.line,
          space_before: g.space_before,
          x: g.x,
          y: g.y,
          w: g.w,
          h: g.h,
          features: g.features
        }
      end)

    # Postgres limits the number of bind parameters per statement.
    rows
    |> Enum.chunk_every(1000)
    |> Enum.each(&repo.insert_all(Glyph, &1))

    {:ok, length(rows)}
  end

  def change_title(%Puzzle{} = puzzle, attrs \\ %{}), do: Puzzle.title_changeset(puzzle, attrs)

  def update_title(%Puzzle{} = puzzle, attrs) do
    puzzle |> Puzzle.title_changeset(attrs) |> Repo.update()
  end

  def delete_puzzle(%Puzzle{} = puzzle) do
    with {:ok, puzzle} <- Repo.delete(puzzle) do
      File.rm(Path.join(uploads_dir(), Path.basename(puzzle.image_path)))
      {:ok, puzzle}
    end
  end

  ## Symbols

  @doc "Substitutes `symbol` with `letter` (nil or \"\" clears it)."
  def assign_letter(%Symbol{} = symbol, letter) do
    symbol |> Symbol.changeset(%{letter: letter}) |> Repo.update()
  end

  def set_ignored(%Symbol{} = symbol, ignored?) do
    symbol |> Symbol.changeset(%{ignored: ignored?}) |> Repo.update()
  end

  def reset_letters(%Puzzle{id: id}) do
    from(s in Symbol, where: s.puzzle_id == ^id)
    |> Repo.update_all(set: [letter: nil, updated_at: DateTime.utc_now(:second)])

    :ok
  end

  @doc """
  Merges `source` into `target`: every glyph of `source` becomes an
  occurrence of `target`. Used when detection split one symbol in two.
  """
  def merge_symbols(%Symbol{} = target, %Symbol{} = source)
      when target.puzzle_id == source.puzzle_id and target.id != source.id do
    Multi.new()
    |> Multi.update_all(:move, from(g in Glyph, where: g.symbol_id == ^source.id),
      set: [symbol_id: target.id]
    )
    |> Multi.run(:letter, fn repo, _ ->
      if is_nil(target.letter) and source.letter,
        do: repo.update(Symbol.changeset(target, %{letter: source.letter})),
        else: {:ok, target}
    end)
    |> Multi.delete(:delete, source)
    |> Repo.transaction()
    |> case do
      {:ok, %{letter: target}} -> {:ok, target}
      {:error, _, reason, _} -> {:error, reason}
    end
  end

  @doc """
  Detaches a single glyph from its symbol into a new symbol of its own.
  Used when detection grouped two different symbols together.
  """
  def detach_glyph(%Glyph{} = glyph) do
    count = Repo.aggregate(from(g in Glyph, where: g.symbol_id == ^glyph.symbol_id), :count)

    if count <= 1 do
      {:error, :only_glyph}
    else
      Repo.transaction(fn ->
        symbol = Repo.insert!(%Symbol{puzzle_id: glyph.puzzle_id})
        Repo.update_all(from(g in Glyph, where: g.id == ^glyph.id), set: [symbol_id: symbol.id])
        symbol
      end)
    end
  end

  @doc """
  Re-clusters all glyphs of a puzzle with a new similarity threshold.

  Letters (and the ignored flag) are carried over to a new symbol when all of
  its glyphs previously agreed on them.
  """
  def regroup(%Puzzle{} = puzzle, threshold) when is_number(threshold) do
    puzzle = get_puzzle!(puzzle.id)
    symbols = Map.new(puzzle.symbols, &{&1.id, &1})

    analyzed =
      puzzle.glyphs
      |> Enum.map(&Map.from_struct/1)
      |> Analysis.cluster(threshold: threshold)

    carried =
      analyzed
      |> Enum.group_by(& &1.cluster, &Map.fetch!(symbols, &1.symbol_id))
      |> Map.new(fn {cluster, old} ->
        {cluster,
         %{
           letter: unanimous(Enum.map(old, & &1.letter)),
           ignored: unanimous(Enum.map(old, & &1.ignored)) || false
         }}
      end)

    Multi.new()
    |> Multi.update(:puzzle, Ecto.Changeset.change(puzzle, threshold: threshold * 1.0))
    |> Multi.delete_all(:glyphs, from(g in Glyph, where: g.puzzle_id == ^puzzle.id))
    |> Multi.delete_all(:symbols, from(s in Symbol, where: s.puzzle_id == ^puzzle.id))
    |> Multi.run(:insert, fn repo, _ ->
      insert_symbols_and_glyphs(repo, puzzle, analyzed, &Map.fetch!(carried, &1))
    end)
    |> Repo.transaction()
    |> case do
      {:ok, _} -> {:ok, get_puzzle!(puzzle.id)}
      {:error, _, reason, _} -> {:error, reason}
    end
  end

  defp unanimous([v | rest]), do: if(Enum.all?(rest, &(&1 == v)), do: v, else: nil)

  ## Helpers

  @doc """
  The deciphered text so far, line by line. Unknown symbols are rendered
  with `unknown` (default "·"), ignored symbols are skipped.
  """
  def plaintext(%Puzzle{glyphs: glyphs, symbols: symbols}, unknown \\ "·") do
    by_id = Map.new(symbols, &{&1.id, &1})

    glyphs
    |> Enum.reject(&Map.fetch!(by_id, &1.symbol_id).ignored)
    |> Enum.chunk_by(& &1.line)
    |> Enum.map_join("\n", fn line ->
      line
      |> Enum.with_index()
      |> Enum.map_join(fn {g, i} ->
        sep = if g.space_before and i > 0, do: " ", else: ""
        sep <> (Map.fetch!(by_id, g.symbol_id).letter || unknown)
      end)
    end)
  end

  def uploads_dir do
    Application.get_env(:subcipher, :uploads_dir) ||
      Application.app_dir(:subcipher, "priv/static/uploads")
  end
end
