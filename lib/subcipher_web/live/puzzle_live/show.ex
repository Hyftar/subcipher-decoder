defmodule SubcipherWeb.PuzzleLive.Show do
  use SubcipherWeb, :live_view

  alias Subcipher.Ciphers
  alias Subcipher.Accounts.Scope
  alias Subcipher.Ciphers.Puzzle
  alias Subcipher.Steps

  import SubcipherWeb.VisibilityComponents, only: [visibility_toggle: 1]

  import SubcipherWeb.StepComponents,
    only: [step_card: 1, output: 1, step_nav: 1, add_step_panel: 1, suggestions_panel: 1]

  # Height (px) at which the typical glyph is displayed in the cipher text.
  @display_height 40
  @english_frequency "ETAOINSHRDLCUMWFGYPBVKJXQZ"

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    case Ciphers.get_puzzle_for(socket.assigns.current_scope, id) do
      nil ->
        {:ok,
         socket
         |> put_flash(:error, "This puzzle doesn't exist, or it is private.")
         |> push_navigate(to: ~p"/")}

      puzzle ->
        {:ok, init(socket, puzzle)}
    end
  end

  defp init(socket, puzzle) do
    socket
    # Only the owner changes it; others see a public puzzle read-only.
    |> assign(:owner?, Scope.owner?(socket.assigns.current_scope, puzzle))
    |> assign(:page_title, puzzle.title)
    |> assign(:selected_symbol_id, nil)
    |> assign(:selected_glyph_id, nil)
    |> assign(:merging, false)
    |> assign(:show_image, false)
    # The glyphs panel of the selected symbol (occurrences, sample, crop),
    # the occurrence it edits (nil = the selected glyph, else the sample)
    # and how it shows it ("original" or "mask": the black and white pass).
    |> assign(:show_glyphs, false)
    |> assign(:edited_glyph_id, nil)
    |> assign(:glyph_view, "original")
    |> assign(:show_add, false)
    # Invalid parameter forms being edited, by step id (kept until fixed).
    |> assign(:step_forms, %{})
    # Number of the step shown (?step=N), or :new for the "add a step" view.
    |> assign(:selected_step, 1)
    # Solver results by {target, input key}, and the one being computed.
    |> assign(:solutions, %{})
    |> assign(:solving, nil)
    |> assign(:shown_suggestions, MapSet.new())
    |> assign(:english_frequency, @english_frequency)
    |> load(puzzle)
  end

  ## Loading & derived state

  defp reload(socket), do: load(socket, Ciphers.get_puzzle!(socket.assigns.puzzle.id))

  defp load(socket, puzzle) do
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
    |> assign(:puzzle, puzzle)
    |> assign(:title_form, to_form(Ciphers.change_title(puzzle)))
    |> assign(:symbols, symbols)
    |> assign(:key, key)
    |> assign(:images, Map.new(puzzle.images, &{&1.id, &1}))
    |> assign(:sections, sections(puzzle))
    |> assign(:duplicates, duplicates)
    |> assign(:solved, Enum.count(active, & &1.symbol.letter))
    |> assign(:symbol_count, length(active))
    |> assign(:plaintext, Ciphers.plaintext(puzzle))
    |> assign_pipeline()
    |> assign(:tolerance, round(puzzle.threshold * 1000))
    |> assign_symbol_suggestions()
    |> keep_selection_valid()
  end

  # Runs the steps. A pictures puzzle starts with the (implicit) symbol
  # substitution of its pictures as step 1; the stored steps follow. A text
  # puzzle's stored steps start from its input text.
  defp assign_pipeline(socket) do
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
    |> assign(:pipeline, pipeline)
    |> assign(:nodes, nodes)
    |> assign(:input_form, input_form)
    |> assign(:final_output, if(results == [], do: source, else: List.last(results).output))
    |> clamp_selected()
  end

  # Keeps the selected step within the existing ones.
  defp clamp_selected(socket) do
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
      |> assign(:symbol_suggestions, frequency)
      |> assign(:symbols_solve_key, {:symbols, :erlang.phash2(Ciphers.symbol_tokens(puzzle))})
    else
      assign(socket, symbol_suggestions: [], symbols_solve_key: nil)
    end
  end

  # The solver card of the picture step: its solution applies letters.
  defp symbols_solver_state(assigns) do
    case solver_state(assigns, assigns.symbols_solve_key) do
      {:ok, solution} ->
        {:ok, Map.put(solution, :use, JS.push("apply_letters", value: %{source: "solver"}))}

      state ->
        state
    end
  end

  # The state of the "Try to solve" card for `key`.
  defp solver_state(%{solving: key}, key), do: :running

  defp solver_state(assigns, key) do
    case Map.get(assigns.solutions, key) do
      nil -> :idle
      {:ok, solution} -> {:ok, Map.put(solution, :applied, solution_applied?(assigns, solution))}
      error -> error
    end
  end

  # Whether a solution is what's currently set (letters or step settings).
  defp solution_applied?(%{symbols: symbols}, %{letters: letters}),
    do: Enum.all?(letters, fn {id, letter} -> match?(%{letter: ^letter}, symbols[id]) end)

  defp solution_applied?(%{current_entry: %{result: r}}, %{params: params}),
    do: Map.merge(r.params, params) == r.params

  defp solution_applied?(_, _), do: false

  defp step_path(socket, number), do: ~p"/puzzles/#{socket.assigns.puzzle}?step=#{number}"

  defp step_number(socket, step_id) do
    Enum.find_value(socket.assigns.pipeline, &(&1.result.step.id == step_id && &1.number))
  end

  defp to_step_form(changeset, step), do: to_form(changeset, as: :step, id: "step-#{step.id}")

  defp find_step(socket, id) do
    Enum.find(socket.assigns.puzzle.steps, &(to_string(&1.id) == to_string(id)))
  end

  # One section per picture. Each picture gets its own display scale so that
  # glyphs from pictures taken at different sizes look alike.
  defp sections(puzzle) do
    by_image = Enum.group_by(puzzle.glyphs, & &1.image_id)

    for {image, index} <- Enum.with_index(puzzle.images, 1) do
      glyphs = Map.get(by_image, image.id, [])

      %{
        image: image,
        index: index,
        glyphs: glyphs,
        lines: lines(glyphs),
        scale: @display_height / max(median(Enum.map(glyphs, & &1.h)), 1)
      }
    end
  end

  # Lines -> words -> glyphs, with each line's vertical extent so glyphs can
  # keep their position relative to the baseline.
  defp lines([]), do: []

  defp lines(glyphs) do
    glyphs
    |> Enum.chunk_by(& &1.line)
    |> Enum.map(fn line ->
      top = line |> Enum.map(& &1.y) |> Enum.min()
      bottom = line |> Enum.map(&(&1.y + &1.h)) |> Enum.max()

      words =
        Enum.chunk_while(
          line,
          [],
          fn g, acc ->
            if g.space_before and acc != [],
              do: {:cont, Enum.reverse(acc), [g]},
              else: {:cont, [g | acc]}
          end,
          fn acc -> {:cont, Enum.reverse(acc), []} end
        )

      %{id: "#{hd(line).image_id}-#{hd(line).line}", top: top, height: bottom - top, words: words}
    end)
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
      else: assign(socket, :selected_glyph_id, nil)
  end

  defp median([]), do: 0
  defp median(values), do: values |> Enum.sort() |> Enum.at(div(length(values), 2))

  @impl true
  def handle_params(params, _uri, socket) do
    selected =
      case params["step"] do
        "new" ->
          :new

        nil ->
          1

        n ->
          case Integer.parse(n) do
            {i, ""} -> i
            _ -> 1
          end
      end

    {:noreply, socket |> assign(:selected_step, selected) |> clamp_selected()}
  end

  ## Events

  # What visitors of a public puzzle may do: look around (select, navigate,
  # open panels). Every other event changes the puzzle: owner only.
  @viewer_events ~w(select_glyph select_symbol deselect key toggle_glyphs edit_glyph glyph_view toggle_image)
  @navigation_keys ~w(ArrowLeft ArrowRight ArrowUp ArrowDown Tab Escape)

  @impl true
  def handle_event("key", %{"key" => key}, %{assigns: %{owner?: false}} = socket)
      when key not in @navigation_keys,
      do: {:noreply, socket}

  def handle_event(event, _params, %{assigns: %{owner?: false}} = socket)
      when event not in @viewer_events,
      do:
        {:noreply,
         put_flash(socket, :error, "This puzzle is read-only: it belongs to someone else.")}

  def handle_event("toggle_public", _params, socket) do
    {:ok, puzzle} = Ciphers.set_public(socket.assigns.puzzle, !socket.assigns.puzzle.public)

    {:noreply,
     socket
     |> assign(:puzzle, %{socket.assigns.puzzle | public: puzzle.public})
     |> put_flash(
       :info,
       if(puzzle.public,
         do: "Public: everyone can see it, read-only.",
         else: "Private: only you can see it."
       )
     )}
  end

  def handle_event("select_glyph", %{"id" => id}, socket) do
    case Enum.find(socket.assigns.puzzle.glyphs, &(to_string(&1.id) == id)) do
      nil -> {:noreply, socket}
      glyph -> {:noreply, select(socket, glyph.symbol_id, glyph.id)}
    end
  end

  def handle_event("select_symbol", %{"id" => id}, socket) do
    case Enum.find(socket.assigns.puzzle.symbols, &(to_string(&1.id) == id)) do
      nil -> {:noreply, socket}
      symbol -> {:noreply, select(socket, symbol.id, nil)}
    end
  end

  def handle_event("deselect", _params, socket) do
    {:noreply, assign(socket, selected_symbol_id: nil, selected_glyph_id: nil, merging: false)}
  end

  def handle_event("key", %{"key" => key} = params, socket) do
    handle_key(key, params["shift"] == true, socket)
  end

  def handle_event("assign", %{"symbol_id" => id, "letter" => letter}, socket) do
    case socket.assigns.symbols[String.to_integer(id)] do
      nil -> {:noreply, socket}
      symbol -> {:noreply, assign_letter(socket, symbol, letter)}
    end
  end

  def handle_event("toggle_ignore", %{"id" => id}, socket) do
    symbol = Map.fetch!(socket.assigns.symbols, String.to_integer(id))
    {:ok, _} = Ciphers.set_ignored(symbol, !symbol.ignored)
    {:noreply, reload(socket)}
  end

  def handle_event("start_merge", _params, socket) do
    {:noreply, assign(socket, :merging, socket.assigns.selected_symbol_id != nil)}
  end

  def handle_event("cancel_merge", _params, socket) do
    {:noreply, assign(socket, :merging, false)}
  end

  def handle_event("detach", _params, socket) do
    glyph = Enum.find(socket.assigns.puzzle.glyphs, &(&1.id == socket.assigns.selected_glyph_id))

    case glyph && Ciphers.detach_glyph(glyph) do
      {:ok, symbol} ->
        {:noreply,
         socket
         |> assign(selected_symbol_id: symbol.id)
         |> put_flash(:info, "This glyph is now a symbol of its own.")
         |> reload()}

      _ ->
        {:noreply, socket}
    end
  end

  def handle_event("toggle_glyphs", _params, socket) do
    {:noreply, update(socket, :show_glyphs, &(!&1))}
  end

  # An occurrence picked in the glyphs panel: edited there, without moving
  # the selection in the text.
  def handle_event("edit_glyph", %{"id" => id}, socket) do
    case find_glyph(socket, id) do
      %{symbol_id: symbol_id} = glyph when symbol_id == socket.assigns.selected_symbol_id ->
        {:noreply, assign(socket, :edited_glyph_id, glyph.id)}

      _ ->
        {:noreply, socket}
    end
  end

  def handle_event("glyph_view", %{"view" => view}, socket) when view in ~w(original mask) do
    {:noreply, assign(socket, :glyph_view, view)}
  end

  def handle_event("set_sample", %{"id" => id}, socket) do
    case find_glyph(socket, id) do
      nil ->
        {:noreply, socket}

      glyph ->
        :ok = Ciphers.set_sample(glyph)
        {:noreply, reload(socket)}
    end
  end

  def handle_event("trim_glyph", %{"id" => id} = params, socket) do
    with %{} = glyph <- find_glyph(socket, id),
         {:ok, _} <- Ciphers.trim_glyph(glyph, Map.take(params, ~w(x y w h))) do
      {:noreply, reload(socket)}
    else
      _ -> {:noreply, socket}
    end
  end

  def handle_event("reset_trim", %{"id" => id}, socket) do
    case find_glyph(socket, id) do
      nil ->
        {:noreply, socket}

      glyph ->
        {:ok, _} = Ciphers.reset_glyph_box(glyph)
        {:noreply, reload(socket)}
    end
  end

  def handle_event("reset_letters", _params, socket) do
    :ok = Ciphers.reset_letters(socket.assigns.puzzle)
    {:noreply, reload(socket)}
  end

  def handle_event("toggle_image", _params, socket) do
    {:noreply, update(socket, :show_image, &(!&1))}
  end

  def handle_event("toggle_add", _params, socket) do
    {:noreply, update(socket, :show_add, &(!&1))}
  end

  def handle_event("add_step", %{"type" => type}, socket) do
    case Steps.add_step(socket.assigns.puzzle, type) do
      {:ok, step} ->
        socket = reload(socket)
        {:noreply, push_patch(socket, to: step_path(socket, step_number(socket, step.id)))}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Could not add this step.")}
    end
  end

  def handle_event("change_step_type", %{"step_id" => id, "type" => type}, socket) do
    with %{} = step <- find_step(socket, id),
         {:ok, _} <- Steps.change_type(step, type) do
      {:noreply,
       socket
       |> update(:step_forms, &Map.delete(&1, step.id))
       |> reload()}
    else
      _ -> {:noreply, put_flash(socket, :error, "Could not change the cipher of this step.")}
    end
  end

  def handle_event("update_input", %{"puzzle" => %{"input_text" => text}}, socket) do
    case Ciphers.update_input_text(socket.assigns.puzzle, text) do
      {:ok, _} -> {:noreply, reload(socket)}
      {:error, _} -> {:noreply, put_flash(socket, :error, "This text is too long.")}
    end
  end

  def handle_event("update_step", %{"step_id" => id} = params, socket) do
    case find_step(socket, id) do
      nil -> {:noreply, socket}
      step -> {:noreply, update_step(socket, step, Map.get(params, "step", %{}))}
    end
  end

  # Runs a solver in the background: for the symbols of the pictures, or
  # for the step shown.
  def handle_event("solve", %{"target" => "symbols"}, socket) do
    puzzle = socket.assigns.puzzle
    key = socket.assigns.symbols_solve_key
    {:noreply, run_solver(socket, key, fn -> Ciphers.solve_letters(puzzle) end)}
  end

  def handle_event("solve", %{"target" => _step_id}, socket) do
    case socket.assigns.current_entry do
      %{result: r, solve_key: key} ->
        {:noreply, run_solver(socket, key, fn -> Steps.solve(r.cipher, r.input, r.params) end)}

      _ ->
        {:noreply, socket}
    end
  end

  def handle_event("apply_letters", %{"source" => source}, socket) do
    letters =
      case source do
        "frequency" ->
          case Ciphers.frequency_letters(socket.assigns.puzzle) do
            nil -> nil
            suggestion -> suggestion.letters
          end

        "solver" ->
          case socket.assigns.solutions[socket.assigns.symbols_solve_key] do
            {:ok, solution} -> solution.letters
            _ -> nil
          end
      end

    if letters do
      :ok = Ciphers.assign_letters(socket.assigns.puzzle, letters)
      {:noreply, reload(socket)}
    else
      {:noreply, socket}
    end
  end

  def handle_event("toggle_suggestions", %{"panel" => panel}, socket) do
    panel = to_string(panel)

    {:noreply,
     update(socket, :shown_suggestions, fn shown ->
       if MapSet.member?(shown, panel),
         do: MapSet.delete(shown, panel),
         else: MapSet.put(shown, panel)
     end)}
  end

  def handle_event("apply_suggestion", %{"id" => id, "params" => params}, socket) do
    case find_step(socket, id) do
      nil -> {:noreply, socket}
      step -> {:noreply, update_step(socket, step, params)}
    end
  end

  def handle_event("delete_step", %{"id" => id}, socket) do
    case find_step(socket, id) do
      nil ->
        {:noreply, socket}

      step ->
        number = step_number(socket, step.id)

        case Steps.delete_step(step) do
          {:ok, _} ->
            socket = socket |> update(:step_forms, &Map.delete(&1, step.id)) |> reload()
            {:noreply, push_patch(socket, to: step_path(socket, max(number - 1, 1)))}

          {:error, :last_step} ->
            {:noreply, put_flash(socket, :error, "A text cipher needs at least one step.")}
        end
    end
  end

  def handle_event("move_step", %{"id" => id, "direction" => direction}, socket)
      when direction in ~w(up down) do
    case find_step(socket, id) do
      nil ->
        {:noreply, socket}

      step ->
        {:ok, _} = Steps.move_step(step, String.to_existing_atom(direction))
        socket = reload(socket)
        {:noreply, push_patch(socket, to: step_path(socket, step_number(socket, step.id)))}
    end
  end

  def handle_event("move_image", %{"id" => id, "direction" => direction}, socket)
      when direction in ~w(up down) do
    image = Enum.find(socket.assigns.puzzle.images, &(to_string(&1.id) == id))

    case image && Ciphers.move_image(image, String.to_existing_atom(direction)) do
      {:ok, puzzle} -> {:noreply, load(socket, puzzle)}
      _ -> {:noreply, put_flash(socket, :error, "Could not move the picture.")}
    end
  end

  def handle_event("make_algorithm", _params, socket) do
    case Subcipher.Algorithms.create_from_puzzle(
           socket.assigns.current_scope,
           socket.assigns.puzzle
         ) do
      {:ok, algorithm} ->
        {:noreply,
         socket
         |> put_flash(:info, "Algorithm created: encode or decode any text with these steps.")
         |> push_navigate(to: ~p"/algorithms/#{algorithm}")}

      {:error, problems} ->
        {:noreply,
         put_flash(
           socket,
           :error,
           "This puzzle can't become an algorithm. " <> Enum.join(problems, " ")
         )}
    end
  end

  def handle_event("delete_image", %{"id" => id}, socket) do
    image = Enum.find(socket.assigns.puzzle.images, &(to_string(&1.id) == id))

    case image && Ciphers.delete_image(image) do
      {:ok, puzzle} ->
        {:noreply, socket |> load(puzzle) |> put_flash(:info, "Picture removed.")}

      {:error, :last_image} ->
        {:noreply, put_flash(socket, :error, "A cipher needs at least one picture.")}

      _ ->
        {:noreply, put_flash(socket, :error, "Could not remove the picture.")}
    end
  end

  def handle_event("regroup", %{"tolerance" => tolerance}, socket) do
    with {t, ""} <- Integer.parse(tolerance),
         true <- t in 5..150,
         {:ok, puzzle} <- Ciphers.regroup(socket.assigns.puzzle, t / 1000) do
      {:noreply,
       socket
       |> assign(selected_symbol_id: nil, selected_glyph_id: nil, merging: false)
       |> load(puzzle)
       |> put_flash(:info, "Symbols regrouped: #{length(puzzle.symbols)} distinct symbols.")}
    else
      _ -> {:noreply, put_flash(socket, :error, "Could not regroup the symbols.")}
    end
  end

  def handle_event("rename_blur", %{"value" => title}, socket) do
    if title == socket.assigns.puzzle.title,
      do: {:noreply, socket},
      else: handle_event("rename", %{"puzzle" => %{"title" => title}}, socket)
  end

  def handle_event("rename", %{"puzzle" => params}, socket) do
    case Ciphers.update_title(socket.assigns.puzzle, params) do
      {:ok, puzzle} ->
        {:noreply,
         socket
         |> assign(:page_title, puzzle.title)
         |> reload()}

      {:error, changeset} ->
        {:noreply, assign(socket, :title_form, to_form(changeset))}
    end
  end

  @impl true
  def handle_async(:solve, {:ok, {key, result}}, socket) do
    {:noreply,
     socket
     |> update(:solutions, &Map.put(&1, key, result))
     |> assign(:solving, nil)}
  end

  def handle_async(:solve, {:exit, _reason}, socket) do
    key = socket.assigns.solving

    {:noreply,
     socket
     |> update(:solutions, &Map.put(&1, key, {:error, "The solver stopped unexpectedly."}))
     |> assign(:solving, nil)}
  end

  defp run_solver(socket, key, fun) do
    socket
    |> assign(:solving, key)
    |> start_async(:solve, fn -> {key, fun.()} end)
  end

  @impl true
  def handle_info({SubcipherWeb.PictureUploadComponent, {:added, puzzle, stats}}, socket) do
    message =
      case stats.new_symbols do
        0 -> "Picture added: #{stats.glyphs} glyphs, all matching known symbols."
        1 -> "Picture added: #{stats.glyphs} glyphs, 1 new symbol."
        n -> "Picture added: #{stats.glyphs} glyphs, #{n} new symbols."
      end

    {:noreply,
     socket
     |> assign(:show_add, false)
     |> load(puzzle)
     |> put_flash(:info, message)}
  end

  defp find_glyph(socket, id) do
    Enum.find(socket.assigns.puzzle.glyphs, &(to_string(&1.id) == to_string(id)))
  end

  # Clicking a symbol while merging merges it into the selected symbol.
  defp select(%{assigns: %{merging: true}} = socket, symbol_id, _glyph_id) do
    %{selected_symbol_id: target_id, symbols: symbols} = socket.assigns

    if symbol_id == target_id do
      assign(socket, :merging, false)
    else
      {:ok, _} = Ciphers.merge_symbols(symbols[target_id], symbols[symbol_id])

      socket
      |> assign(:merging, false)
      |> put_flash(:info, "Symbols merged.")
      |> reload()
    end
  end

  defp select(socket, symbol_id, glyph_id) do
    assign(socket,
      selected_symbol_id: symbol_id,
      selected_glyph_id: glyph_id,
      edited_glyph_id: nil
    )
  end

  defp handle_key("Escape", _shift, socket) do
    if socket.assigns.merging,
      do: {:noreply, assign(socket, :merging, false)},
      else: {:noreply, assign(socket, selected_symbol_id: nil, selected_glyph_id: nil)}
  end

  # ← / →: previous / next character of the text.
  defp handle_key("ArrowLeft", _shift, socket), do: {:noreply, move_in_text(socket, -1)}
  defp handle_key("ArrowRight", _shift, socket), do: {:noreply, move_in_text(socket, 1)}

  # ↑ / ↓ (and Tab / Shift+Tab): previous / next symbol of the symbol key.
  defp handle_key(key, shift, socket) when key in ~w(ArrowDown ArrowUp Tab) do
    backwards = key == "ArrowUp" or (key == "Tab" and shift)
    {:noreply, move_in_key(socket, if(backwards, do: -1, else: 1))}
  end

  defp handle_key(key, _shift, socket) when key in ~w(Backspace Delete) do
    case selected_symbol(socket) do
      nil -> {:noreply, socket}
      symbol -> {:noreply, assign_letter(socket, symbol, nil)}
    end
  end

  defp handle_key(key, _shift, socket) do
    case {selected_symbol(socket), String.length(key)} do
      {%{} = symbol, 1} -> {:noreply, assign_letter(socket, symbol, key)}
      _ -> {:noreply, socket}
    end
  end

  defp selected_symbol(socket), do: socket.assigns.symbols[socket.assigns.selected_symbol_id]

  # Moves character by character through the text, in reading order (picture
  # after picture), skipping ignored symbols. Stops at both ends. When a
  # symbol is selected without a specific character (e.g. from the key), the
  # move starts from its first occurrence.
  defp move_in_text(socket, step) do
    %{puzzle: puzzle, symbols: symbols} = socket.assigns
    glyphs = Enum.reject(puzzle.glyphs, &symbols[&1.symbol_id].ignored)
    current = Enum.find_index(glyphs, &(&1.id == socket.assigns.selected_glyph_id))

    target =
      cond do
        glyphs == [] ->
          nil

        current ->
          # Clamped: no wrapping (Enum.at/2 would read negative indexes from the end).
          Enum.at(glyphs, (current + step) |> max(0) |> min(length(glyphs) - 1))

        socket.assigns.selected_symbol_id ->
          Enum.find(glyphs, &(&1.symbol_id == socket.assigns.selected_symbol_id)) ||
            hd(glyphs)

        step > 0 ->
          hd(glyphs)

        true ->
          List.last(glyphs)
      end

    case target do
      nil -> socket
      g -> assign(socket, selected_symbol_id: g.symbol_id, selected_glyph_id: g.id)
    end
  end

  # Moves through the symbol key (most frequent first), skipping ignored ones.
  defp move_in_key(socket, step) do
    ids = for %{symbol: s} <- socket.assigns.key, !s.ignored, do: s.id

    case ids do
      [] ->
        socket

      ids ->
        index = Enum.find_index(ids, &(&1 == socket.assigns.selected_symbol_id))

        next =
          case index do
            nil -> if step > 0, do: 0, else: -1
            i -> rem(i + step + length(ids), length(ids))
          end

        assign(socket, selected_symbol_id: Enum.at(ids, next), selected_glyph_id: nil)
    end
  end

  # Valid parameters are saved; invalid ones stay in the form, with errors,
  # until fixed (the step keeps decoding with its last valid parameters).
  defp update_step(socket, step, params) do
    case Steps.update_params(step, params) do
      {:ok, _step} ->
        socket |> update(:step_forms, &Map.delete(&1, step.id)) |> reload()

      {:error, changeset} ->
        socket
        |> update(:step_forms, &Map.put(&1, step.id, to_step_form(changeset, step)))
        |> assign_pipeline()
    end
  end

  defp assign_letter(socket, symbol, letter) do
    case Ciphers.assign_letter(symbol, letter) do
      {:ok, _} -> reload(socket)
      {:error, _} -> put_flash(socket, :error, "A substitution is at most 3 characters.")
    end
  end

  ## Rendering

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div id="puzzle-page" class="space-y-6">
        <div class="flex flex-wrap items-center gap-3">
          <.link navigate={~p"/"} class="btn btn-ghost btn-square" aria-label="Back">
            <.icon name="hero-arrow-left" class="size-6" />
          </.link>
          <%= if @owner? do %>
            <.form
              for={@title_form}
              id="title-form"
              phx-submit="rename"
              class="flex-1 min-w-48"
            >
              <input
                type="text"
                name={@title_form[:title].name}
                value={@title_form[:title].value}
                phx-blur="rename_blur"
                aria-label="Title"
                class="w-full bg-transparent text-2xl font-bold tracking-tight rounded-md px-1 -mx-1 focus:outline-none focus:ring-2 focus:ring-primary/40"
              />
            </.form>
          <% else %>
            <h1 class="flex-1 min-w-48 text-2xl font-bold tracking-tight">{@puzzle.title}</h1>
          <% end %>
          <div :if={Puzzle.pictures?(@puzzle)} class="flex items-center gap-3 text-sm">
            <span class="text-base-content/70" id="progress">
              {@solved} / {@symbol_count} symbols
            </span>
            <progress class="progress progress-primary w-32" value={@solved} max={@symbol_count} />
          </div>
          <.visibility_toggle :if={@owner?} public={@puzzle.public} />
          <button
            :if={@owner?}
            type="button"
            id="make-algorithm"
            class="btn btn-soft btn-primary"
            phx-click="make_algorithm"
            title="Copy these steps into an algorithm to encode and decode any text"
          >
            <.icon name="hero-cog-6-tooth" class="size-5" /> Make an algorithm
          </button>
        </div>

        <div
          :if={!@owner?}
          id="read-only"
          class="flex items-center gap-3 rounded-xl bg-info/10 px-4 py-3 text-sm"
        >
          <.icon name="hero-eye" class="size-5 shrink-0 text-info" />
          <p>
            A puzzle shared by someone else: you can look around, but not change it.
          </p>
        </div>

        <.step_nav puzzle={@puzzle} nodes={@nodes} selected={@selected_step} />

        <%= cond do %>
          <% @selected_step == :new -> %>
            <.add_step_panel />
          <% @current_entry -> %>
            <.step_card
              number={@current_entry.number}
              result={@current_entry.result}
              form={@current_entry.form}
              suggestions={@current_entry.suggestions}
              suggestions_shown={
                MapSet.member?(@shown_suggestions, to_string(@current_entry.result.step.id))
              }
              solver_state={
                if Steps.implements?(@current_entry.result.cipher, :solve, 2),
                  do: solver_state(assigns, @current_entry.solve_key)
              }
              can_move_up={@current_entry.number != hd(@pipeline).number}
              can_move_down={@current_entry.number != List.last(@pipeline).number}
              can_delete={Puzzle.pictures?(@puzzle) or length(@pipeline) > 1}
              input_form={@current_entry.number == hd(@pipeline).number && @input_form}
            />
          <% true -> %>
            <.symbol_step
              puzzle={@puzzle}
              selected_symbol_id={@selected_symbol_id}
              selected_glyph_id={@selected_glyph_id}
              merging={@merging}
              key={@key}
              images={@images}
              symbols={@symbols}
              sections={@sections}
              duplicates={@duplicates}
              plaintext={@plaintext}
              show_image={@show_image}
              show_add={@show_add}
              show_glyphs={@show_glyphs}
              edited_glyph_id={@edited_glyph_id}
              current_scope={@current_scope}
              glyph_view={@glyph_view}
              tolerance={@tolerance}
              english_frequency={@english_frequency}
              symbol_suggestions={@symbol_suggestions}
              suggestions_shown={MapSet.member?(@shown_suggestions, "symbols")}
              symbol_solver={
                %{
                  state: symbols_solver_state(assigns),
                  start: JS.push("solve", value: %{target: "symbols"})
                }
              }
            />
        <% end %>

        <section
          :if={@selected_step != :new and @selected_step != length(@nodes) and length(@nodes) > 1}
          id="final-output-block"
          class="rounded-2xl border border-base-300 bg-base-100 p-4 sm:p-6 space-y-2"
        >
          <h2 class="flex items-center justify-between text-sm font-semibold">
            Final output
            <.link
              patch={~p"/puzzles/#{@puzzle}?step=#{length(@nodes)}"}
              class="link link-hover text-xs font-normal"
            >
              Go to step {length(@nodes)} <.icon name="hero-arrow-right" class="size-3" />
            </.link>
          </h2>
          <.output id="final-output" text={@final_output} />
        </section>
      </div>
    </Layouts.app>
    """
  end

  attr :puzzle, :any, required: true
  attr :selected_symbol_id, :any, required: true
  attr :selected_glyph_id, :any, required: true
  attr :merging, :boolean, required: true
  attr :key, :list, required: true
  attr :images, :map, required: true
  attr :symbols, :map, required: true
  attr :sections, :list, required: true
  attr :duplicates, :any, required: true
  attr :plaintext, :string, required: true
  attr :show_image, :boolean, required: true
  attr :show_add, :boolean, required: true
  attr :show_glyphs, :boolean, required: true
  attr :edited_glyph_id, :any, required: true
  attr :current_scope, :any, required: true
  attr :glyph_view, :string, required: true
  attr :tolerance, :integer, required: true
  attr :english_frequency, :string, required: true
  attr :symbol_suggestions, :list, required: true
  attr :symbol_solver, :map, required: true
  attr :suggestions_shown, :boolean, required: true

  # Step 1 of a pictures puzzle: the symbols of the pictures, substituted by
  # hand, with the symbol key.
  defp symbol_step(assigns) do
    ~H"""
    <div
      id="puzzle"
      phx-hook="CipherKeys"
      data-selected={to_string(@selected_symbol_id != nil)}
      data-scroll-to={
        cond do
          @selected_glyph_id -> "glyph-#{@selected_glyph_id}"
          @selected_symbol_id -> "symbol-#{@selected_symbol_id}"
          true -> nil
        end
      }
    >
      <div class="grid gap-6 lg:grid-cols-[minmax(0,1fr)_20rem]">
        <div class="space-y-6 min-w-0">
          <.selection_bar
            symbol={@symbols[@selected_symbol_id]}
            glyph_id={@selected_glyph_id}
            merging={@merging}
            key={@key}
            images={@images}
            show_glyphs={@show_glyphs}
          />

          <.glyph_panel
            :if={@show_glyphs and @selected_symbol_id != nil and !@merging}
            entry={Enum.find(@key, &(&1.symbol.id == @selected_symbol_id))}
            glyph_id={@edited_glyph_id || @selected_glyph_id}
            images={@images}
            view={@glyph_view}
          />

          <section
            id="cipher-text"
            class="rounded-2xl border border-base-300 bg-base-100 p-4 sm:p-6 space-y-5 overflow-x-auto"
            phx-click="deselect"
          >
            <div
              :for={section <- @sections}
              id={"section-#{section.image.id}"}
              class="space-y-5 [&+&]:pt-6 [&+&]:border-t-2 [&+&]:border-base-300"
            >
              <div
                :if={length(@sections) > 1}
                class="flex items-center justify-between text-xs font-semibold uppercase tracking-wider text-base-content/50"
              >
                Picture {section.index}
                <.picture_controls section={section} count={length(@sections)} />
              </div>
              <div
                :for={line <- section.lines}
                id={"line-#{line.id}"}
                class="flex flex-wrap gap-x-5 gap-y-3 pb-5 border-b border-dashed border-base-300 last:border-0 last:pb-0"
              >
                <div :for={word <- line.words} class="flex items-start gap-1">
                  <.glyph_cell
                    :for={g <- word}
                    glyph={g}
                    line={line}
                    symbol={@symbols[g.symbol_id]}
                    image={section.image}
                    scale={section.scale}
                    selected={g.symbol_id == @selected_symbol_id}
                    current={g.id == @selected_glyph_id}
                    merging={@merging}
                    duplicate={MapSet.member?(@duplicates, @symbols[g.symbol_id].letter)}
                  />
                </div>
              </div>
            </div>
          </section>

          <section
            id="step-1-output"
            class="rounded-2xl border border-base-300 bg-base-100 p-4 sm:p-6 space-y-2"
          >
            <h2 class="text-xs font-semibold uppercase tracking-wider text-base-content/50">
              Output
            </h2>
            <.output id="plaintext" text={@plaintext} />
          </section>

          <section class="rounded-2xl border border-base-300 bg-base-100 p-4 sm:p-6">
            <.suggestions_panel
              id="symbols"
              suggestions={@symbol_suggestions}
              solver={@symbol_solver}
              shown={@suggestions_shown}
            />
          </section>

          <section class="rounded-2xl border border-base-300 bg-base-100">
            <button
              type="button"
              phx-click="toggle_image"
              class="w-full flex items-center justify-between px-4 py-2 text-sm font-semibold"
            >
              {if length(@puzzle.images) > 1,
                do: "Original pictures & detected symbols",
                else: "Original picture & detected symbols"}
              <.icon
                name={if @show_image, do: "hero-chevron-up", else: "hero-chevron-down"}
                class="size-4"
              />
            </button>
            <div :if={@show_image} class="p-4 pt-0 space-y-4">
              <figure
                :for={section <- @sections}
                id={"picture-#{section.image.id}"}
                class="space-y-2"
              >
                <figcaption
                  :if={length(@sections) > 1}
                  class="flex items-center justify-between text-xs font-semibold uppercase tracking-wider text-base-content/50"
                >
                  Picture {section.index}
                  <span class="flex items-center gap-1">
                    <.picture_controls
                      section={section}
                      count={length(@sections)}
                      id_prefix="panel-"
                    />
                    <button
                      type="button"
                      class="btn btn-ghost btn-sm normal-case tracking-normal font-normal"
                      phx-click="delete_image"
                      phx-value-id={section.image.id}
                      data-confirm="Remove this picture? Symbols that only appear in it are removed too."
                    >
                      <.icon name="hero-trash" class="size-5" /> Remove
                    </button>
                  </span>
                </figcaption>
                <div class="relative">
                  <img
                    src={section.image.path}
                    alt={"Cipher picture #{section.index}"}
                    class="block w-full h-auto rounded-lg"
                  />
                  <button
                    :for={g <- section.glyphs}
                    type="button"
                    phx-click="select_glyph"
                    phx-value-id={g.id}
                    aria-label="Select symbol"
                    class={[
                      "absolute rounded-[2px] ring-1 transition",
                      cond do
                        g.symbol_id == @selected_symbol_id -> "ring-2 ring-primary bg-primary/25"
                        @symbols[g.symbol_id].ignored -> "ring-base-content/20"
                        @symbols[g.symbol_id].letter -> "ring-success/70 bg-success/10"
                        true -> "ring-warning/70 hover:bg-warning/20"
                      end
                    ]}
                    style={box_style(g, section.image)}
                  />
                </div>
              </figure>
              <.form
                for={%{}}
                id="regroup-form"
                phx-submit="regroup"
                class="mt-4 flex flex-wrap items-end gap-3 text-sm"
              >
                <label class="flex-1 min-w-56">
                  <span class="block font-medium mb-1">
                    Grouping tolerance
                    <span class="text-base-content/60 font-normal">
                      (higher = more glyphs considered identical)
                    </span>
                  </span>
                  <input
                    type="range"
                    name="tolerance"
                    min="5"
                    max="150"
                    value={@tolerance}
                    class="range range-primary range-sm"
                  />
                </label>
                <button
                  type="submit"
                  class="btn"
                  data-confirm="Regroup all symbols? Letters are kept when all glyphs of a new group agree."
                >
                  Regroup symbols
                </button>
              </.form>
            </div>
          </section>

          <section id="add-picture" class="rounded-2xl border border-base-300 bg-base-100">
            <button
              type="button"
              phx-click="toggle_add"
              class="w-full flex items-center justify-between px-4 py-2 text-sm font-semibold"
            >
              <span class="flex items-center gap-2">
                <.icon name="hero-plus-circle" class="size-4" /> Add a picture to this cipher
              </span>
              <.icon
                name={if @show_add, do: "hero-chevron-up", else: "hero-chevron-down"}
                class="size-4"
              />
            </button>
            <div :if={@show_add} class="p-4 pt-0 space-y-3">
              <p class="text-sm text-base-content/70">
                Symbols in the new picture are matched with the ones you already have, so
                your letters apply to it right away.
              </p>
              <.live_component
                module={SubcipherWeb.PictureUploadComponent}
                id="add-picture-upload"
                puzzle={@puzzle}
                scope={@current_scope}
              />
            </div>
          </section>
        </div>

        <.symbol_key
          key={@key}
          images={@images}
          selected_symbol_id={@selected_symbol_id}
          duplicates={@duplicates}
          english_frequency={@english_frequency}
        />
      </div>
    </div>
    """
  end

  attr :section, :map, required: true
  attr :count, :integer, required: true, doc: "number of pictures in the puzzle"
  attr :id_prefix, :string, default: "", doc: "keeps ids unique when rendered twice"

  # Moves a picture earlier/later in the reading order.
  defp picture_controls(assigns) do
    ~H"""
    <span class="flex items-center normal-case tracking-normal font-normal">
      <button
        type="button"
        id={"#{@id_prefix}move-up-#{@section.image.id}"}
        class="btn btn-ghost btn-sm btn-square"
        phx-click="move_image"
        phx-value-id={@section.image.id}
        phx-value-direction="up"
        disabled={@section.index == 1}
        aria-label={"Move picture #{@section.index} up"}
        title="Move up"
      >
        <.icon name="hero-arrow-up" class="size-5" />
      </button>
      <button
        type="button"
        id={"#{@id_prefix}move-down-#{@section.image.id}"}
        class="btn btn-ghost btn-sm btn-square"
        phx-click="move_image"
        phx-value-id={@section.image.id}
        phx-value-direction="down"
        disabled={@section.index == @count}
        aria-label={"Move picture #{@section.index} down"}
        title="Move down"
      >
        <.icon name="hero-arrow-down" class="size-5" />
      </button>
    </span>
    """
  end

  attr :symbol, :any, required: true
  attr :glyph_id, :any, required: true
  attr :merging, :boolean, required: true
  attr :show_glyphs, :boolean, default: false
  attr :key, :list, required: true
  attr :images, :map, required: true

  defp selection_bar(%{symbol: nil} = assigns) do
    ~H"""
    <div class="rounded-xl bg-base-200/60 px-4 py-3 text-sm text-base-content/70 flex items-center gap-2">
      <.icon name="hero-cursor-arrow-rays" class="size-5 shrink-0" />
      <p id="keyboard-help">
        Click a symbol, then type the letter it stands for. Every identical symbol is replaced
        at once. <kbd class="kbd kbd-xs">←</kbd> <kbd class="kbd kbd-xs">→</kbd>
        previous / next character, <kbd class="kbd kbd-xs">↑</kbd> <kbd class="kbd kbd-xs">↓</kbd>
        previous / next symbol of the key, <kbd class="kbd kbd-xs">⌫</kbd>
        clears.
      </p>
    </div>
    """
  end

  defp selection_bar(assigns) do
    assigns =
      assign(assigns, :entry, Enum.find(assigns.key, &(&1.symbol.id == assigns.symbol.id)))

    ~H"""
    <div
      id="selection-bar"
      class={[
        "rounded-xl px-4 py-3 flex flex-wrap items-center gap-3 text-sm transition-colors",
        if(@merging, do: "bg-warning/15 ring-1 ring-warning", else: "bg-primary/10")
      ]}
    >
      <span class="grid place-items-center size-12 rounded-lg bg-base-100 shrink-0">
        <.glyph_image glyph={@entry.sample} image={@images[@entry.sample.image_id]} box={40} />
      </span>
      <div class="flex-1 min-w-40">
        <%= if @merging do %>
          <p class="font-medium">Click another symbol to merge it into this one.</p>
          <p class="text-base-content/70">Use this when the same symbol was detected twice.</p>
        <% else %>
          <p class="font-medium">
            {@entry.count} occurrence{if @entry.count > 1, do: "s"} ·
            <span :if={@symbol.letter}>
              stands for <span class="font-mono text-primary text-base">{@symbol.letter}</span>
            </span>
            <span :if={!@symbol.letter} class="text-base-content/70">type a letter…</span>
          </p>
        <% end %>
      </div>
      <div class="flex flex-wrap gap-2">
        <%= if @merging do %>
          <button type="button" class="btn" phx-click="cancel_merge">Cancel</button>
        <% else %>
          <button
            type="button"
            class={["btn", @show_glyphs && "btn-active"]}
            phx-click="toggle_glyphs"
            id="glyphs-button"
            aria-expanded={to_string(@show_glyphs)}
            title="Its occurrences: choose the one shown, trim a crop"
          >
            <.icon name="hero-squares-2x2" class="size-5" /> Glyphs
          </button>
          <button type="button" class="btn" phx-click="start_merge" id="merge-button">
            <.icon name="hero-arrows-pointing-in" class="size-5" /> Merge…
          </button>
          <button
            :if={@glyph_id && @entry.count > 1}
            type="button"
            class="btn btn-sm"
            phx-click="detach"
            id="detach-button"
            title="This occurrence is actually a different symbol"
          >
            <.icon name="hero-scissors" class="size-4" /> Split this one off
          </button>
          <button
            type="button"
            class="btn"
            phx-click="toggle_ignore"
            phx-value-id={@symbol.id}
            title="Hide noise or decorations from the text"
          >
            <.icon name={if @symbol.ignored, do: "hero-eye", else: "hero-eye-slash"} class="size-5" />
            {if @symbol.ignored, do: "Restore", else: "Ignore"}
          </button>
        <% end %>
      </div>
    </div>
    """
  end

  attr :entry, :any, required: true, doc: "the selected symbol's key entry"
  attr :glyph_id, :any, required: true, doc: "the occurrence to edit (else the sample)"
  attr :images, :map, required: true
  attr :view, :string, required: true, doc: "\"original\" or \"mask\""

  # The selected symbol's occurrences: choose the one shown for it (and used
  # by algorithms), and trim the crop of any of them.
  defp glyph_panel(%{entry: nil} = assigns), do: ~H""

  defp glyph_panel(assigns) do
    glyph =
      Enum.find(assigns.entry.glyphs, &(&1.id == assigns.glyph_id)) || assigns.entry.sample

    assigns =
      assigns
      |> assign(:glyph, glyph)
      |> assign(:image, assigns.images[glyph.image_id])

    ~H"""
    <section
      id="glyph-panel"
      class="rounded-2xl border border-base-300 bg-base-100 p-4 grid gap-5 md:grid-cols-[minmax(0,1fr)_18rem]"
    >
      <div class="space-y-2 min-w-0">
        <h3 class="text-sm font-semibold">
          Occurrences <span class="text-base-content/50 font-normal">· {@entry.count}</span>
        </h3>
        <p class="text-xs text-base-content/60">
          Pick one to trim it. The <.icon name="hero-star-solid" class="size-3 text-warning" />
          sample is the one shown in the symbol key and drawn by algorithms.
        </p>
        <div id="occurrences" class="flex flex-wrap gap-1.5 max-h-56 overflow-y-auto p-0.5">
          <button
            :for={g <- @entry.glyphs}
            type="button"
            id={"occurrence-#{g.id}"}
            phx-click="edit_glyph"
            phx-value-id={g.id}
            aria-pressed={to_string(g.id == @glyph.id)}
            title={if g.detected_box, do: "Trimmed", else: nil}
            class={[
              "relative grid place-items-center size-12 rounded-lg bg-base-200/60 transition",
              "hover:bg-base-200 hover:-translate-y-0.5 focus:outline-none focus-visible:ring-2 focus-visible:ring-primary",
              g.id == @glyph.id && "ring-2 ring-primary bg-primary/10"
            ]}
          >
            <.glyph_image glyph={g} image={@images[g.image_id]} box={40} />
            <.icon
              :if={g.id == @entry.sample.id}
              name="hero-star-solid"
              class="absolute -top-1 -right-1 size-4 text-warning drop-shadow"
            />
            <.icon
              :if={g.detected_box}
              name="hero-scissors"
              class="absolute -bottom-1 -right-1 size-3.5 text-base-content/60"
            />
          </button>
        </div>
      </div>

      <div class="space-y-2">
        <div class="flex items-center justify-between gap-2">
          <h3 class="text-sm font-semibold">Crop</h3>
          <div id="glyph-view" class="join">
            <button
              :for={{view, label} <- [{"original", "Original"}, {"mask", "Black & white"}]}
              type="button"
              id={"view-#{view}"}
              class={["btn btn-sm join-item", @view == view && "btn-primary"]}
              phx-click="glyph_view"
              phx-value-view={view}
              aria-pressed={to_string(@view == view)}
            >
              {label}
            </button>
          </div>
        </div>
        <div
          id="glyph-trim"
          phx-hook="GlyphTrim"
          phx-update="ignore"
          data-own-keys
          data-glyph-id={@glyph.id}
          data-image={@image.path}
          data-box={Jason.encode!(%{x: @glyph.x, y: @glyph.y, w: @glyph.w, h: @glyph.h})}
          data-detected={@glyph.detected_box && Jason.encode!(@glyph.detected_box)}
          data-view={@view}
          class="relative h-56 w-full overflow-hidden rounded-lg bg-base-200 select-none touch-none"
        >
        </div>
        <p class="text-xs text-base-content/60">
          Drag an edge, or focus it and use the arrow keys (<kbd class="kbd kbd-xs">Shift</kbd>: 5 px).
        </p>
        <div class="flex flex-wrap gap-2">
          <%= if @glyph.id == @entry.sample.id do %>
            <span class="badge badge-warning badge-soft gap-1">
              <.icon name="hero-star-solid" class="size-3" /> Sample
            </span>
          <% else %>
            <button
              type="button"
              id="set-sample"
              class="btn btn-sm"
              phx-click="set_sample"
              phx-value-id={@glyph.id}
            >
              <.icon name="hero-star" class="size-5" /> Use as sample
            </button>
          <% end %>
          <button
            :if={@glyph.detected_box}
            type="button"
            id="reset-trim"
            class="btn btn-sm btn-ghost"
            phx-click="reset_trim"
            phx-value-id={@glyph.id}
          >
            <.icon name="hero-arrow-uturn-left" class="size-5" /> Reset crop
          </button>
        </div>
      </div>
    </section>
    """
  end

  attr :glyph, :any, required: true
  attr :line, :map, required: true
  attr :symbol, :any, required: true
  attr :image, :any, required: true
  attr :scale, :float, required: true
  attr :selected, :boolean, required: true
  attr :current, :boolean, required: true
  attr :merging, :boolean, required: true
  attr :duplicate, :boolean, required: true

  defp glyph_cell(assigns) do
    ~H"""
    <button
      type="button"
      id={"glyph-#{@glyph.id}"}
      phx-click="select_glyph"
      phx-value-id={@glyph.id}
      class={[
        "group flex flex-col items-center rounded-md px-0.5 pt-1 transition",
        "focus:outline-none focus-visible:ring-2 focus-visible:ring-primary",
        @symbol.ignored && "opacity-25",
        @selected && !@merging && "bg-primary/15",
        @selected && @merging && "bg-warning/25",
        !@selected && @merging && "hover:bg-warning/15 cursor-copy",
        !@selected && !@merging && "hover:bg-base-200",
        @current && "ring-2 ring-primary"
      ]}
    >
      <span class="relative block" style={"height: #{px(@line.height * @scale)}"}>
        <span
          class="block"
          style={"margin-top: #{px((@glyph.y - @line.top) * @scale)}"}
        >
          <.glyph_image glyph={@glyph} image={@image} scale={@scale} />
        </span>
      </span>
      <span
        :if={!@symbol.ignored}
        class={[
          "mt-1 min-w-6 h-7 border-b-2 text-center font-mono text-lg leading-7 uppercase",
          @symbol.letter && !@duplicate && "border-transparent text-primary font-semibold",
          @symbol.letter && @duplicate && "border-transparent text-warning font-semibold",
          !@symbol.letter && "border-base-content/30 text-transparent",
          @selected && "border-primary!"
        ]}
      >
        {@symbol.letter || "_"}
      </span>
    </button>
    """
  end

  attr :key, :list, required: true
  attr :images, :map, required: true
  attr :selected_symbol_id, :any, required: true
  attr :duplicates, :any, required: true
  attr :english_frequency, :string, required: true

  defp symbol_key(assigns) do
    ~H"""
    <aside class="space-y-3 lg:sticky lg:top-20 lg:self-start">
      <div class="flex items-center justify-between">
        <h2 class="font-semibold">Symbol key</h2>
        <button
          type="button"
          class="btn btn-ghost btn-sm"
          phx-click="reset_letters"
          data-confirm="Clear every letter?"
        >
          <.icon name="hero-arrow-path" class="size-5" /> Reset
        </button>
      </div>
      <p class="text-xs text-base-content/60">
        Most frequent first. English letters by frequency:
        <span class="font-mono tracking-wider">{@english_frequency}</span>
      </p>
      <ul
        id="symbol-key"
        class="rounded-2xl border border-base-300 bg-base-100 divide-y divide-base-300 lg:max-h-[calc(100vh-12rem)] overflow-y-auto"
      >
        <li
          :for={entry <- @key}
          id={"symbol-#{entry.symbol.id}"}
          class={[
            "flex items-center gap-3 px-3 py-2 transition-colors",
            entry.symbol.id == @selected_symbol_id && "bg-primary/10",
            entry.symbol.ignored && "opacity-40"
          ]}
        >
          <button
            type="button"
            phx-click="select_symbol"
            phx-value-id={entry.symbol.id}
            class="flex flex-1 items-center gap-3 min-w-0 text-left"
          >
            <span class="grid place-items-center size-10 rounded-md bg-base-200/60 shrink-0">
              <.glyph_image glyph={entry.sample} image={@images[entry.sample.image_id]} box={32} />
            </span>
            <span class="text-xs text-base-content/70 leading-tight">
              <span class="block font-medium text-base-content">×{entry.count}</span>
              {if entry.symbol.ignored, do: "ignored", else: "#{Float.round(entry.frequency, 1)}%"}
            </span>
          </button>
          <form
            :if={!entry.symbol.ignored}
            phx-change="assign"
            phx-submit="assign"
            id={"assign-#{entry.symbol.id}"}
          >
            <input type="hidden" name="symbol_id" value={entry.symbol.id} />
            <input
              type="text"
              name="letter"
              value={entry.symbol.letter}
              maxlength="3"
              autocomplete="off"
              spellcheck="false"
              aria-label="Letter"
              phx-debounce="150"
              class={[
                "input input-sm w-14 text-center font-mono uppercase text-base",
                MapSet.member?(@duplicates, entry.symbol.letter) && "input-warning"
              ]}
            />
          </form>
        </li>
      </ul>
      <p :if={MapSet.size(@duplicates) > 0} class="text-xs text-warning">
        <.icon name="hero-exclamation-triangle" class="size-4 align-text-bottom" />
        Used by several symbols: {Enum.join(@duplicates, ", ")}
      </p>
    </aside>
    """
  end

  attr :glyph, :any, required: true
  attr :image, :any, required: true, doc: "the picture the glyph comes from"
  attr :scale, :float, default: nil, doc: "explicit display scale"
  attr :box, :integer, default: nil, doc: "fit the glyph in a square of this size (px)"

  # Renders a glyph by cropping the original picture with CSS.
  defp glyph_image(assigns) do
    %{glyph: g, image: image} = assigns
    pad = 2
    w = g.w + 2 * pad
    h = g.h + 2 * pad
    scale = assigns.scale || assigns.box / max(w, h)

    style =
      [
        "width: #{px(w * scale)}",
        "height: #{px(h * scale)}",
        "background-image: url('#{image.path}')",
        "background-size: #{px(image.width * scale)} #{px(image.height * scale)}",
        "background-position: #{px(-(g.x - pad) * scale)} #{px(-(g.y - pad) * scale)}"
      ]
      |> Enum.join("; ")

    assigns = assign(assigns, :style, style)

    ~H"""
    <span class="block bg-no-repeat rounded-sm" style={@style} aria-hidden="true"></span>
    """
  end

  defp px(v), do: "#{Float.round(v * 1.0, 2)}px"

  defp box_style(g, image) do
    "left: #{g.x / image.width * 100}%; top: #{g.y / image.height * 100}%; " <>
      "width: #{g.w / image.width * 100}%; height: #{g.h / image.height * 100}%"
  end
end
