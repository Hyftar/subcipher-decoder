defmodule Subcipher.Ciphers do
  @moduledoc """
  Cipher puzzles. A puzzle has one or more pictures (`Image`) of its cipher
  text; the glyphs detected in them are grouped into symbols shared by all
  pictures, which the user substitutes with letters.
  """

  import Ecto.Query, warn: false

  alias Ecto.Multi
  alias Subcipher.Repo
  alias Subcipher.Accounts.Scope
  alias Subcipher.Ciphers.{Analysis, Glyph, Image, Puzzle, Symbol}

  def default_threshold, do: Analysis.default_threshold()

  ## Puzzles

  @doc """
  Lists the puzzles of the scope's user, most recent first, with their
  pictures and glyph and symbol counts (none without a user).
  """
  def list_puzzles(nil), do: []

  def list_puzzles(%Scope{user: user}),
    do: list_puzzles_where(dynamic([p], p.user_id == ^user.id))

  @doc "The public puzzles of other users (like `list_puzzles/1`)."
  def list_public_puzzles(scope) do
    case scope do
      %Scope{user: user} ->
        dynamic([p], p.public and (p.user_id != ^user.id or is_nil(p.user_id)))

      nil ->
        dynamic([p], p.public)
    end
    |> list_puzzles_where()
  end

  defp list_puzzles_where(condition) do
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
        where: ^condition,
        order_by: [desc: p.inserted_at, desc: p.id],
        preload: [images: ^from(i in Image, order_by: i.position)],
        select: %{
          puzzle: p,
          glyph_count: coalesce(g.n, 0),
          symbol_count: coalesce(s.n, 0),
          solved_count: coalesce(s.solved, 0)
        }
    )
  end

  @doc "The puzzle with `id` (an integer or a string from a URL), or `nil`."
  def get_puzzle(id) do
    case parse_id(id) do
      nil -> nil
      id -> if Repo.get(Puzzle, id), do: get_puzzle!(id)
    end
  end

  @doc """
  The puzzle with `id` if the scope may see it (its own, or public), else
  `nil` (missing and private look the same).
  """
  def get_puzzle_for(scope, id) do
    case get_puzzle(id) do
      nil -> nil
      puzzle -> if Scope.can_view?(scope, puzzle), do: puzzle
    end
  end

  @doc "Makes a puzzle public (seen by everyone, read-only) or private."
  def set_public(%Puzzle{} = puzzle, public) when is_boolean(public) do
    puzzle |> Ecto.Changeset.change(public: public) |> Repo.update()
  end

  @doc "`id` as a positive integer, or `nil` when it isn't one."
  def parse_id(id) when is_integer(id) and id > 0, do: id

  def parse_id(id) when is_binary(id) do
    case Integer.parse(id) do
      {id, ""} when id > 0 -> id
      _ -> nil
    end
  end

  def parse_id(_), do: nil

  @doc """
  Gets a puzzle with its pictures, symbols and glyphs (in reading order:
  picture by picture).
  """
  def get_puzzle!(id) do
    Puzzle
    |> Repo.get!(id)
    |> Repo.preload(
      images: from(i in Image, order_by: i.position),
      symbols: from(s in Symbol, order_by: s.id),
      steps: from(s in Subcipher.Steps.Step, order_by: s.position),
      glyphs:
        from(g in Glyph,
          join: i in assoc(g, :image),
          order_by: [i.position, g.position]
        )
    )
  end

  @doc """
  Creates a puzzle from its first picture and the glyphs the browser
  detected in it (see `Analysis.parse_detection/1`).

  `image` is `%{path: tmp_path, ext: ".png", width: w, height: h}`; the file
  is copied to the uploads directory. The puzzle belongs to the scope's user.
  """
  def create_puzzle(%Scope{user: user}, attrs, image, glyphs, opts \\ []) do
    threshold = Keyword.get(opts, :threshold, default_threshold())

    changeset =
      %Puzzle{user_id: user.id}
      |> Puzzle.changeset(Map.put(stringify(attrs), "threshold", threshold))

    with {:ok, _} <- validate(changeset),
         {:ok, stored} <- store_file(image) do
      analyzed = Analysis.analyze(glyphs, threshold: threshold)

      Multi.new()
      |> Multi.insert(:puzzle, changeset)
      |> Multi.insert(:image, fn %{puzzle: puzzle} -> image_struct(puzzle, stored, image, 0) end)
      |> Multi.run(:glyphs, fn repo, %{puzzle: puzzle, image: img} ->
        insert_glyphs(repo, puzzle.id, Enum.map(analyzed, &Map.put(&1, :image_id, img.id)))
      end)
      |> Repo.transaction()
      |> case do
        {:ok, %{puzzle: puzzle}} ->
          {:ok, get_puzzle!(puzzle.id)}

        {:error, _step, reason, _} ->
          remove_file(stored)
          {:error, reason}
      end
    end
  end

  @doc """
  Adds another picture of the cipher text to a puzzle.

  New glyphs are matched against the puzzle's existing symbols (which keep
  their letters and the user's corrections); glyphs matching none of them
  become new symbols. Returns `{:ok, puzzle, %{glyphs: n, new_symbols: m}}`.
  """
  def add_image(%Puzzle{} = puzzle, image, glyphs) do
    puzzle = get_puzzle!(puzzle.id)

    with {:ok, stored} <- store_file(image) do
      matched =
        glyphs
        |> Analysis.layout()
        |> Analysis.match(Enum.map(puzzle.glyphs, &Map.from_struct/1),
          threshold: puzzle.threshold
        )

      position = puzzle.images |> Enum.map(& &1.position) |> Enum.max(fn -> -1 end)

      Multi.new()
      |> Multi.insert(:image, image_struct(puzzle, stored, image, position + 1))
      |> Multi.run(:glyphs, fn repo, %{image: img} ->
        insert_glyphs(repo, puzzle.id, Enum.map(matched, &Map.put(&1, :image_id, img.id)))
      end)
      |> Repo.transaction()
      |> case do
        {:ok, _} ->
          new_symbols = matched |> Enum.map(& &1.cluster) |> Enum.reject(&is_nil/1) |> Enum.uniq()

          {:ok, get_puzzle!(puzzle.id),
           %{glyphs: length(matched), new_symbols: length(new_symbols)}}

        {:error, _step, reason, _} ->
          remove_file(stored)
          {:error, reason}
      end
    end
  end

  @doc """
  Removes a picture and its glyphs. Symbols that only appeared in that
  picture are removed too. A puzzle keeps at least one picture.
  """
  def delete_image(%Image{} = image) do
    count = Repo.aggregate(from(i in Image, where: i.puzzle_id == ^image.puzzle_id), :count)

    if count <= 1 do
      {:error, :last_image}
    else
      Multi.new()
      |> Multi.delete_all(:glyphs, from(g in Glyph, where: g.image_id == ^image.id))
      |> Multi.delete(:image, image)
      |> Multi.delete_all(
        :orphans,
        from(s in Symbol,
          as: :symbol,
          where: s.puzzle_id == ^image.puzzle_id,
          where: not exists(from g in Glyph, where: g.symbol_id == parent_as(:symbol).id)
        )
      )
      |> Repo.transaction()
      |> case do
        {:ok, _} ->
          remove_file(image.path)
          {:ok, get_puzzle!(image.puzzle_id)}

        {:error, _, reason, _} ->
          {:error, reason}
      end
    end
  end

  @doc """
  Sets the reading order of a puzzle's pictures. `image_ids` must list every
  picture of the puzzle exactly once.
  """
  def reorder_images(%Puzzle{id: puzzle_id}, image_ids) do
    current = Repo.all(from i in Image, where: i.puzzle_id == ^puzzle_id, select: i.id)

    if Enum.sort(current) == Enum.sort(image_ids) do
      Repo.transaction(fn ->
        # Positions are unique per puzzle: park every picture on a temporary
        # negative position first, then assign the final ones.
        for {id, i} <- Enum.with_index(image_ids, 1) do
          Repo.update_all(from(im in Image, where: im.id == ^id), set: [position: -i])
        end

        for {id, i} <- Enum.with_index(image_ids) do
          Repo.update_all(from(im in Image, where: im.id == ^id), set: [position: i])
        end
      end)

      {:ok, get_puzzle!(puzzle_id)}
    else
      {:error, :invalid_order}
    end
  end

  @doc "Moves a picture one step earlier (`:up`) or later (`:down`) in the reading order."
  def move_image(%Image{} = image, direction) when direction in [:up, :down] do
    puzzle = get_puzzle!(image.puzzle_id)
    ids = Enum.map(puzzle.images, & &1.id)
    index = Enum.find_index(ids, &(&1 == image.id))
    target = if direction == :up, do: index - 1, else: index + 1

    if target < 0 or target >= length(ids) do
      {:ok, puzzle}
    else
      ids
      |> List.replace_at(index, Enum.at(ids, target))
      |> List.replace_at(target, image.id)
      |> then(&reorder_images(puzzle, &1))
    end
  end

  defp store_file(image) do
    filename = "#{Ecto.UUID.generate()}#{image.ext}"

    with :ok <- File.mkdir_p(uploads_dir()),
         :ok <- File.cp(image.path, Path.join(uploads_dir(), filename)) do
      {:ok, "/uploads/#{filename}"}
    end
  end

  defp remove_file(public_path), do: File.rm(Path.join(uploads_dir(), Path.basename(public_path)))

  defp image_struct(puzzle, stored, image, position) do
    %Image{
      puzzle_id: puzzle.id,
      path: stored,
      width: image.width,
      height: image.height,
      position: position
    }
  end

  defp validate(%Ecto.Changeset{valid?: true} = cs), do: {:ok, cs}
  defp validate(cs), do: {:error, %{cs | action: :insert}}

  defp stringify(attrs), do: Map.new(attrs, fn {k, v} -> {to_string(k), v} end)

  # Inserts glyphs (each with an `:image_id`). Glyphs with a `:symbol_id`
  # join that existing symbol; the others carry a `:cluster` index and one
  # new symbol is created per cluster, with `symbol_attrs.(cluster)` as
  # extra attributes.
  defp insert_glyphs(repo, puzzle_id, glyphs, symbol_attrs \\ fn _ -> %{} end) do
    now = DateTime.utc_now(:second)

    clusters =
      glyphs
      |> Enum.filter(&is_nil(Map.get(&1, :symbol_id)))
      |> Enum.map(& &1.cluster)
      |> Enum.uniq()
      |> Enum.sort()

    {_, symbol_ids} =
      repo.insert_all(
        Symbol,
        Enum.map(clusters, fn c ->
          Map.merge(
            %{puzzle_id: puzzle_id, ignored: false, inserted_at: now, updated_at: now},
            symbol_attrs.(c)
          )
        end),
        returning: [:id]
      )

    # insert_all returns rows in insertion order, i.e. cluster order.
    id_by_cluster = clusters |> Enum.zip(Enum.map(symbol_ids, & &1.id)) |> Map.new()

    rows =
      Enum.map(glyphs, fn g ->
        %{
          puzzle_id: puzzle_id,
          image_id: g.image_id,
          symbol_id: Map.get(g, :symbol_id) || Map.fetch!(id_by_cluster, g.cluster),
          position: g.position,
          line: g.line,
          space_before: g.space_before,
          x: g.x,
          y: g.y,
          w: g.w,
          h: g.h,
          features: g.features,
          detected_box: Map.get(g, :detected_box)
        }
      end)

    # Postgres limits the number of bind parameters per statement.
    rows
    |> Enum.chunk_every(1000)
    |> Enum.each(&repo.insert_all(Glyph, &1))

    {:ok, length(rows)}
  end

  @doc """
  Creates a puzzle whose input is text (`attrs`: title, input_text), with a
  first decoding step of cipher `first_step_type`, owned by the scope's user.
  `step_params` (e.g. a guessed key) are set on that step instead of the
  defaults.
  """
  def create_text_puzzle(%Scope{user: user}, attrs, first_step_type, step_params \\ %{}) do
    changeset =
      Puzzle.text_changeset(
        %Puzzle{user_id: user.id},
        Map.put(stringify(attrs), "threshold", default_threshold())
      )

    Multi.new()
    |> Multi.insert(:puzzle, changeset)
    |> Multi.run(:step, fn _repo, %{puzzle: puzzle} ->
      Subcipher.Steps.add_step(puzzle, first_step_type)
    end)
    |> Multi.run(:params, fn _repo, %{step: step} ->
      if step_params == %{},
        do: {:ok, step},
        else: Subcipher.Steps.update_params(step, step_params)
    end)
    |> Repo.transaction()
    |> case do
      {:ok, %{puzzle: puzzle}} -> {:ok, get_puzzle!(puzzle.id)}
      {:error, _step, reason, _} -> {:error, reason}
    end
  end

  @doc """
  Creates a puzzle whose input is text (`attrs`: title, input_text), decoded
  by `steps` (`[%{"type" => type, "params" => params}]`, in order: those of
  an algorithm), owned by the scope's user.
  """
  def create_text_puzzle_with_steps(%Scope{user: user}, attrs, [_ | _] = steps) do
    changeset =
      Puzzle.text_changeset(
        %Puzzle{user_id: user.id},
        Map.put(stringify(attrs), "threshold", default_threshold())
      )

    steps
    |> Enum.with_index(1)
    |> Enum.reduce(Multi.insert(Multi.new(), :puzzle, changeset), fn
      {%{"type" => type, "params" => params}, position}, multi ->
        Multi.insert(multi, {:step, position}, fn %{puzzle: puzzle} ->
          %Subcipher.Steps.Step{
            puzzle_id: puzzle.id,
            position: position,
            type: Subcipher.Steps.cipher!(type).type(),
            params: params
          }
        end)
    end)
    |> Repo.transaction()
    |> case do
      {:ok, %{puzzle: puzzle}} -> {:ok, get_puzzle!(puzzle.id)}
      {:error, _step, reason, _} -> {:error, reason}
    end
  end

  def change_text_puzzle(attrs \\ %{}), do: Puzzle.text_changeset(%Puzzle{}, attrs)

  def update_input_text(%Puzzle{} = puzzle, text) do
    puzzle |> Puzzle.input_text_changeset(%{input_text: text}) |> Repo.update()
  end

  def change_title(%Puzzle{} = puzzle, attrs \\ %{}), do: Puzzle.title_changeset(puzzle, attrs)

  def update_title(%Puzzle{} = puzzle, attrs) do
    puzzle |> Puzzle.title_changeset(attrs) |> Repo.update()
  end

  def delete_puzzle(%Puzzle{} = puzzle) do
    paths = Repo.all(from i in Image, where: i.puzzle_id == ^puzzle.id, select: i.path)

    with {:ok, puzzle} <- Repo.delete(puzzle) do
      Enum.each(paths, &remove_file/1)
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

  ## Samples and trimming

  @doc """
  The occurrence shown for `symbol` among its `glyphs` (in reading order):
  the one chosen with `set_sample/2`, else the first.
  """
  def sample_glyph(%Symbol{sample_glyph_id: id}, glyphs) do
    (id && Enum.find(glyphs, &(&1.id == id))) || List.first(glyphs)
  end

  @doc "Makes `glyph` the occurrence shown for its symbol (and used by algorithms)."
  def set_sample(%Glyph{} = glyph) do
    from(s in Symbol, where: s.id == ^glyph.symbol_id)
    |> Repo.update_all(set: [sample_glyph_id: glyph.id])

    :ok
  end

  @doc """
  Changes the crop of `glyph` to `box` (`x`, `y`, `w`, `h`, string or atom
  keys), kept inside its picture. The box found by detection is remembered,
  for `reset_glyph_box/1`. The glyph's descriptor (used for grouping) is
  unchanged.
  """
  def trim_glyph(%Glyph{} = glyph, box) do
    image = Repo.get!(Image, glyph.image_id)

    with {:ok, %{"x" => x, "y" => y, "w" => w, "h" => h}} <- cast_box(box),
         x0 = clamp(x, 0, image.width - 1),
         y0 = clamp(y, 0, image.height - 1),
         x1 = clamp(x + w, x0 + 1, image.width),
         y1 = clamp(y + h, y0 + 1, image.height) do
      glyph
      |> Ecto.Changeset.change(
        x: x0,
        y: y0,
        w: x1 - x0,
        h: y1 - y0,
        detected_box: glyph.detected_box || box_map(glyph)
      )
      |> Repo.update()
    end
  end

  @doc "Restores the box detection found for `glyph`."
  def reset_glyph_box(%Glyph{detected_box: nil} = glyph), do: {:ok, glyph}

  def reset_glyph_box(%Glyph{detected_box: box} = glyph) do
    glyph
    |> Ecto.Changeset.change(
      x: box["x"],
      y: box["y"],
      w: box["w"],
      h: box["h"],
      detected_box: nil
    )
    |> Repo.update()
  end

  defp box_map(g), do: %{"x" => g.x, "y" => g.y, "w" => g.w, "h" => g.h}

  defp cast_box(box) do
    values =
      for key <- ~w(x y w h) do
        case Map.get(box, key, Map.get(box, String.to_existing_atom(key))) do
          v when is_integer(v) -> v
          v when is_float(v) -> round(v)
          v when is_binary(v) -> parse_int(v)
          _ -> nil
        end
      end

    case values do
      [x, y, w, h] when is_integer(x) and is_integer(y) and is_integer(w) and is_integer(h) ->
        {:ok, %{"x" => x, "y" => y, "w" => w, "h" => h}}

      _ ->
        {:error, :invalid_box}
    end
  end

  defp parse_int(v) do
    case Integer.parse(v) do
      {n, ""} -> n
      _ -> nil
    end
  end

  defp clamp(v, lo, hi), do: v |> max(lo) |> min(hi)

  @doc """
  Re-clusters all glyphs of a puzzle with a new similarity threshold.

  Letters (and the ignored flag) are carried over to a new symbol when all of
  its glyphs previously agreed on them.
  """
  def regroup(%Puzzle{} = puzzle, threshold) when is_number(threshold) do
    puzzle = get_puzzle!(puzzle.id)
    symbols = Map.new(puzzle.symbols, &{&1.id, &1})

    # Glyphs keep their picture (`:image_id`); sizes are compared per picture.
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
      glyphs = Enum.map(analyzed, &Map.put(&1, :symbol_id, nil))
      insert_glyphs(repo, puzzle.id, glyphs, &Map.fetch!(carried, &1))
    end)
    |> Multi.run(:samples, fn repo, _ -> carry_samples(repo, puzzle) end)
    |> Repo.transaction()
    |> case do
      {:ok, _} -> {:ok, get_puzzle!(puzzle.id)}
      {:error, _, reason, _} -> {:error, reason}
    end
  end

  # The chosen samples stay samples of the symbol their glyph now belongs
  # to (glyphs are reinserted: they are found again by position).
  defp carry_samples(repo, puzzle) do
    sample_ids =
      for s <- puzzle.symbols, s.sample_glyph_id, into: MapSet.new(), do: s.sample_glyph_id

    positions = for g <- puzzle.glyphs, MapSet.member?(sample_ids, g.id), do: g.position

    from(g in Glyph,
      where: g.puzzle_id == ^puzzle.id and g.position in ^positions,
      order_by: g.position,
      select: {g.id, g.symbol_id}
    )
    |> repo.all()
    |> Enum.uniq_by(&elem(&1, 1))
    |> Enum.each(fn {glyph_id, symbol_id} ->
      repo.update_all(from(s in Symbol, where: s.id == ^symbol_id),
        set: [sample_glyph_id: glyph_id]
      )
    end)

    {:ok, nil}
  end

  defp unanimous([v | rest]), do: if(Enum.all?(rest, &(&1 == v)), do: v, else: nil)

  ## Suggestions for the symbols of the pictures

  @english_order ~w(E T A O I N S H R D L C U M W F G Y P B V K J X Q Z)

  @doc """
  The symbols of the pictures in reading order, as symbol ids with `:gap`
  between words (and lines); ignored symbols are left out.
  """
  def symbol_tokens(%Puzzle{glyphs: glyphs, symbols: symbols}) do
    ignored = for s <- symbols, s.ignored, into: MapSet.new(), do: s.id

    glyphs
    |> Enum.reject(&MapSet.member?(ignored, &1.symbol_id))
    |> Enum.chunk_by(&{&1.image_id, &1.line})
    |> Enum.flat_map(fn line ->
      [
        :gap
        | Enum.flat_map(
            line,
            &if(&1.space_before, do: [:gap, &1.symbol_id], else: [&1.symbol_id])
          )
      ]
    end)
    |> Enum.drop_while(&(&1 == :gap))
  end

  # Letters set by the user (single letters A-Z), kept by the suggestions.
  defp known_letters(puzzle) do
    for s <- puzzle.symbols,
        not s.ignored,
        is_binary(s.letter),
        s.letter =~ ~r/^[A-Z]$/,
        into: %{},
        do: {s.id, s.letter}
  end

  @doc """
  Suggests letters for the symbols without one, by frequency: the most
  frequent symbols get the most frequent English letters not used yet.
  Returns `%{label, letters: %{symbol_id => letter}, reason, preview}`, or
  nil when every symbol has a letter.
  """
  def frequency_letters(%Puzzle{} = puzzle) do
    known = known_letters(puzzle)

    unassigned =
      puzzle
      |> symbol_tokens()
      |> Enum.reject(&(&1 == :gap or Map.has_key?(known, &1)))
      |> Enum.frequencies()
      |> Enum.sort_by(fn {id, n} -> {-n, id} end)
      |> Enum.map(&elem(&1, 0))

    if unassigned != [] do
      free_letters = @english_order -- Map.values(known)
      letters = unassigned |> Enum.zip(Stream.cycle(free_letters)) |> Map.new()

      %{
        label: "Frequency match",
        letters: letters,
        reason:
          "The most frequent symbols get the most frequent English letters (E, T, A, O, I, N…) not used yet: a starting point, fix the wrong ones by hand." <>
            if(known == %{}, do: "", else: " Your #{map_size(known)} letter(s) are kept."),
        preview: preview_with(puzzle, letters)
      }
    end
  end

  @doc """
  Solves the symbols with `Subcipher.Solver` (keeping the letters already
  set). Returns `{:ok, %{label, letters, reason, preview}}` or
  `{:error, message}`. Takes about a second or two: run it in the background.
  """
  def solve_letters(%Puzzle{} = puzzle) do
    known = known_letters(puzzle)

    case Subcipher.Solver.solve(symbol_tokens(puzzle), fixed: known) do
      {:ok, %{mapping: letters}} ->
        decoded = plaintext(with_letters(puzzle, letters), "?")
        kept = if known == %{}, do: "", else: " Your #{map_size(known)} letter(s) were kept."

        {:ok,
         %{
           label: "Solver",
           letters: letters,
           reason: Subcipher.Solver.explain(decoded) <> kept,
           preview: Subcipher.Steps.preview(decoded)
         }}

      {:error, :too_short} ->
        {:error, "Too few symbols to solve: at least 8 are needed."}
    end
  end

  @doc "Sets the letters of several symbols at once (`%{symbol_id => letter}`)."
  def assign_letters(%Puzzle{id: puzzle_id}, letters) do
    now = DateTime.utc_now(:second)

    Repo.transaction(fn ->
      for {symbol_id, letter} <- letters do
        from(s in Symbol, where: s.id == ^symbol_id and s.puzzle_id == ^puzzle_id)
        |> Repo.update_all(set: [letter: letter, updated_at: now])
      end
    end)

    :ok
  end

  defp with_letters(puzzle, letters) do
    symbols =
      Enum.map(puzzle.symbols, fn s ->
        case Map.fetch(letters, s.id) do
          {:ok, letter} -> %{s | letter: letter}
          :error -> s
        end
      end)

    %{puzzle | symbols: symbols}
  end

  defp preview_with(puzzle, letters),
    do: puzzle |> with_letters(letters) |> plaintext() |> Subcipher.Steps.preview()

  ## Helpers

  @doc """
  The deciphered text so far, line by line, with a blank line between
  pictures. Unknown symbols are rendered with `unknown` (default "·"),
  ignored symbols are skipped.
  """
  def plaintext(%Puzzle{glyphs: glyphs, symbols: symbols}, unknown \\ "·") do
    by_id = Map.new(symbols, &{&1.id, &1})

    glyphs
    |> Enum.reject(&Map.fetch!(by_id, &1.symbol_id).ignored)
    |> Enum.chunk_by(& &1.image_id)
    |> Enum.map_join("\n\n", fn image_glyphs ->
      image_glyphs
      |> Enum.chunk_by(& &1.line)
      |> Enum.map_join("\n", fn line ->
        line
        |> Enum.with_index()
        |> Enum.map_join(fn {g, i} ->
          sep = if g.space_before and i > 0, do: " ", else: ""
          sep <> (Map.fetch!(by_id, g.symbol_id).letter || unknown)
        end)
      end)
    end)
  end

  def uploads_dir do
    Application.get_env(:subcipher, :uploads_dir) ||
      Application.app_dir(:subcipher, "priv/static/uploads")
  end
end
