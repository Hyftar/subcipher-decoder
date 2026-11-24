defmodule SubcipherWeb.PuzzleLive.Assigns do
  @moduledoc """
  Assigns of the puzzle page derived from the puzzle: its symbols and symbol
  key, the decoding steps and their results, suggestions; and lookups.
  """
  use SubcipherWeb, :verified_routes

  import Phoenix.Component, only: [assign: 2, to_form: 1, to_form: 2]

  alias Phoenix.LiveView.JS
  alias Subcipher.{Ciphers, Steps}
  alias Subcipher.Ciphers.Puzzle
  alias SubcipherWeb.PuzzleLive.Sections

  @doc "Reloads the puzzle, and everything derived from it."
  def reload(socket), do: load(socket, Ciphers.get_puzzle!(socket.assigns.puzzle.id))

  def load(socket, puzzle) do
    symbols = Map.new(puzzle.symbols, &{&1.id, &1})
    by_symbol = Enum.group_by(puzzle.glyphs, & &1.symbol_id)
    visible = Enum.reject(puzzle.glyphs, &symbols[&1.symbol_id].ignored)
    total = max(length(visible), 1)
    # Reading order across pictures (glyphs are loaded picture by picture).
    order = puzzle.glyphs |> Enum.with_index() |> Map.new(fn {g, i} -> {g.id, i} end)

    key =
      puzzle.symbols
      |> Enum.map(fn s ->
        glyphs = Map.get(by_symbol, s.id, [])

        %{
          symbol: s,
          sample: Ciphers.sample_glyph(s, glyphs),
          glyphs: glyphs,
          count: length(glyphs),
          frequency: if(s.ignored, do: 0.0, else: length(glyphs) / total * 100)
        }
      end)
      |> Enum.reject(&is_nil(&1.sample))
      |> Enum.sort_by(&{&1.symbol.ignored, -&1.count, Map.fetch!(order, hd(&1.glyphs).id)})

    duplicates =
      puzzle.symbols
      |> Enum.reject(&(&1.ignored or is_nil(&1.letter)))
      |> Enum.frequencies_by(& &1.letter)
      |> Enum.filter(fn {_, n} -> n > 1 end)
      |> MapSet.new(fn {l, _} -> l end)

    active = Enum.reject(key, & &1.symbol.ignored)

    socket
    |> assign(
      puzzle: puzzle,
      title_form: to_form(Ciphers.change_title(puzzle)),
      symbols: symbols,
      key: key,
      images: Map.new(puzzle.images, &{&1.id, &1}),
      sections: Sections.build(puzzle),
      duplicates: duplicates,
      solved: Enum.count(active, & &1.symbol.letter),
      symbol_count: length(active),
      plaintext: Ciphers.plaintext(puzzle)
    )
    |> assign_pipeline()
    |> assign(tolerance: round(puzzle.threshold * 1000))
    |> assign_symbol_suggestions()
    |> keep_selection_valid()
  end

  # Runs the steps. A pictures puzzle starts with the (implicit) symbol
  # substitution of its pictures as step 1; the stored steps follow. A text
  # puzzle's stored steps start from its input text.
  def assign_pipeline(socket) do
    %{puzzle: puzzle} = socket.assigns
    pictures? = Puzzle.pictures?(puzzle)
    source = if pictures?, do: socket.assigns.plaintext, else: puzzle.input_text
    offset = if pictures?, do: 1, else: 0
    results = Steps.run(source, puzzle.steps)

    pipeline =
      for {result, i} <- Enum.with_index(results) do
        step = result.step

        form =
          Map.get_lazy(socket.assigns.step_forms, step.id, fn ->
            step.type |> Steps.params_changeset(step.params) |> to_step_form(step)
          end)

        %{number: i + 1 + offset, result: result, form: form}
      end

    picture_node =
      if pictures?,
        do: [%{number: 1, label: "Symbol substitution", icon: "hero-photo"}],
        else: []

    nodes =
      picture_node ++ Enum.map(pipeline, &%{number: &1.number, label: &1.result.cipher.name()})

    input_form =
      if not pictures?, do: to_form(%{"input_text" => puzzle.input_text}, as: :puzzle)

    socket
    |> assign(
      pipeline: pipeline,
      nodes: nodes,
      input_form: input_form,
      final_output: if(results == [], do: source, else: List.last(results).output)
    )
    |> clamp_selected()
  end

  # Keeps the selected step within the existing ones.
  def clamp_selected(socket) do
    %{nodes: nodes, selected_step: selected} = socket.assigns
    count = length(nodes)

    selected =
      cond do
        count == 0 -> :new
        selected == :new -> :new
        selected > count -> count
        selected < 1 -> 1
        true -> selected
      end

    # Suggestions are only computed for the step shown.
    current =
      case Enum.find(socket.assigns.pipeline, &(&1.number == selected)) do
        nil ->
          nil

        %{result: r} = entry ->
          entry
          |> Map.put(:suggestions, Steps.suggestions(r.cipher, r.input, r.params))
          |> Map.put(:solve_key, {:step, r.step.id, :erlang.phash2(r.input)})
      end

    assign(socket, selected_step: selected, current_entry: current)
  end

  # Suggestions for the symbols of the pictures (step 1 of a pictures puzzle).
  defp assign_symbol_suggestions(socket) do
    puzzle = socket.assigns.puzzle

    if Puzzle.pictures?(puzzle) do
      use_frequency = JS.push("apply_letters", value: %{source: "frequency"})

      frequency =
        case Ciphers.frequency_letters(puzzle) do
          nil -> []
          s -> [Map.merge(s, %{applied: false, use: use_frequency})]
        end

      socket
      |> assign(
        symbol_suggestions: frequency,
        symbols_solve_key: {:symbols, :erlang.phash2(Ciphers.symbol_tokens(puzzle))}
      )
    else
      assign(socket, symbol_suggestions: [], symbols_solve_key: nil)
    end
  end

  def step_path(socket, number), do: ~p"/puzzles/#{socket.assigns.puzzle}?step=#{number}"

  def step_number(socket, step_id) do
    Enum.find_value(socket.assigns.pipeline, &(&1.result.step.id == step_id && &1.number))
  end

  def to_step_form(changeset, step), do: to_form(changeset, as: :step, id: "step-#{step.id}")

  def find_step(socket, id) do
    Enum.find(socket.assigns.puzzle.steps, &(to_string(&1.id) == to_string(id)))
  end

  defp keep_selection_valid(socket) do
    %{symbols: symbols, puzzle: puzzle} = socket.assigns

    socket =
      if Map.has_key?(symbols, socket.assigns.selected_symbol_id),
        do: socket,
        else: assign(socket, selected_symbol_id: nil, merging: false)

    glyph = Enum.find(puzzle.glyphs, &(&1.id == socket.assigns.selected_glyph_id))

    if glyph && glyph.symbol_id == socket.assigns.selected_symbol_id,
      do: socket,
      else: assign(socket, selected_glyph_id: nil)
  end

  def find_glyph(socket, id) do
    Enum.find(socket.assigns.puzzle.glyphs, &(to_string(&1.id) == to_string(id)))
  end
end
