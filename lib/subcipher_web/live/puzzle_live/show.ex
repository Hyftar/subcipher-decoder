defmodule SubcipherWeb.PuzzleLive.Show do
  @moduledoc """
  A puzzle: its decoding steps, one at a time (?step=N). A pictures puzzle
  starts with the symbol substitution of its pictures (step 1).

  Events are handled by modules by concern, in `Events`: `Selection`,
  `Symbol`, `Glyph`, `Picture` (pictures puzzles), `Step`, `Suggestion`
  and `Puzzle`.
  """
  use SubcipherWeb, :live_view

  alias Subcipher.{Ciphers, Steps}
  alias Subcipher.Accounts.Scope
  alias Subcipher.Ciphers.Puzzle

  alias SubcipherWeb.PuzzleLive.{Assigns, Events, Solver}

  import SubcipherWeb.Components.{AddStepPanel, StepCard, StepNav}

  import SubcipherWeb.PuzzleLive.{FinalOutput, Header, ReadOnlyNotice, SymbolStep}

  @english_frequency "ETAOINSHRDLCUMWFGYPBVKJXQZ"

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    case Ciphers.get_puzzle_for(socket.assigns.current_scope, id) do
      nil ->
        socket
        |> put_flash(:error, "This puzzle doesn't exist, or it is private.")
        |> push_navigate(to: ~p"/")
        |> wrap(:ok)

      puzzle ->
        socket |> init(puzzle) |> wrap(:ok)
    end
  end

  defp init(socket, puzzle) do
    socket
    |> assign(
      # Only the owner changes it; others see a public puzzle read-only.
      owner?: Scope.owner?(socket.assigns.current_scope, puzzle),
      page_title: puzzle.title,
      selected_symbol_id: nil,
      selected_glyph_id: nil,
      merging: false,
      show_image: false,
      # The glyphs panel of the selected symbol (occurrences, sample, crop),
      # the occurrence it edits (nil = the selected glyph, else the sample)
      # and how it shows it ("original" or "mask": the black and white pass).
      show_glyphs: false,
      edited_glyph_id: nil,
      glyph_view: "original",
      show_add: false,
      # Invalid parameter forms being edited, by step id (kept until fixed).
      step_forms: %{},
      # Number of the step shown (?step=N), or :new for the "add a step" view.
      selected_step: 1,
      # Solver results by {target, input key}, and the one being computed.
      solutions: %{},
      solving: nil,
      # Suggestion panels opened by the user ("symbols" or a step id): they
      # can spoil the puzzle, so they stay hidden until asked for.
      shown_suggestions: MapSet.new(),
      english_frequency: @english_frequency
    )
    |> Assigns.load(puzzle)
  end

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

    socket
    |> assign(selected_step: selected)
    |> Assigns.clamp_selected()
    |> wrap(:noreply)
  end

  ## Events

  @selection_events ~w(select_glyph select_symbol deselect key)
  @symbol_events ~w(assign toggle_ignore start_merge cancel_merge detach reset_letters regroup)
  @glyph_events ~w(toggle_glyphs edit_glyph glyph_view set_sample trim_glyph reset_trim)
  @picture_events ~w(toggle_image toggle_add move_image delete_image)
  @step_events ~w(add_step change_step_type update_input update_step apply_suggestion delete_step move_step)
  @suggestion_events ~w(toggle_suggestions solve apply_letters)
  @puzzle_events ~w(toggle_public make_algorithm rename_blur rename)

  # What visitors of a public puzzle may do: look around (select, navigate,
  # open panels). Every other event changes the puzzle: owner only.
  @viewer_events ~w(select_glyph select_symbol deselect key toggle_glyphs edit_glyph glyph_view toggle_image)
  @navigation_keys ~w(ArrowLeft ArrowRight ArrowUp ArrowDown Tab Escape)

  @impl true
  def handle_event("key", %{"key" => key}, %{assigns: %{owner?: false}} = socket)
      when key not in @navigation_keys,
      do: wrap(socket, :noreply)

  def handle_event(event, _params, %{assigns: %{owner?: false}} = socket)
      when event not in @viewer_events do
    socket
    |> put_flash(:error, "This puzzle is read-only: it belongs to someone else.")
    |> wrap(:noreply)
  end

  def handle_event(event, params, socket) when event in @selection_events,
    do: Events.Selection.handle_event(event, params, socket)

  def handle_event(event, params, socket) when event in @symbol_events,
    do: Events.Symbol.handle_event(event, params, socket)

  def handle_event(event, params, socket) when event in @glyph_events,
    do: Events.Glyph.handle_event(event, params, socket)

  def handle_event(event, params, socket) when event in @picture_events,
    do: Events.Picture.handle_event(event, params, socket)

  def handle_event(event, params, socket) when event in @step_events,
    do: Events.Step.handle_event(event, params, socket)

  def handle_event(event, params, socket) when event in @suggestion_events,
    do: Events.Suggestion.handle_event(event, params, socket)

  def handle_event(event, params, socket) when event in @puzzle_events,
    do: Events.Puzzle.handle_event(event, params, socket)

  @impl true
  def handle_async(:solve, result, socket), do: Solver.handle_async(result, socket)

  @impl true
  def handle_info({SubcipherWeb.PictureUploadComponent, {:added, puzzle, stats}}, socket) do
    message =
      case stats.new_symbols do
        0 -> "Picture added: #{stats.glyphs} glyphs, all matching known symbols."
        1 -> "Picture added: #{stats.glyphs} glyphs, 1 new symbol."
        n -> "Picture added: #{stats.glyphs} glyphs, #{n} new symbols."
      end

    socket
    |> assign(show_add: false)
    |> Assigns.load(puzzle)
    |> put_flash(:info, message)
    |> wrap(:noreply)
  end

  ## Rendering

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div id="puzzle-page" class="space-y-6">
        <.puzzle_header
          puzzle={@puzzle}
          title_form={@title_form}
          owner={@owner?}
          solved={@solved}
          symbol_count={@symbol_count}
        />
        <.read_only_notice :if={!@owner?} />
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
                  do: Solver.solver_state(assigns, @current_entry.solve_key)
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
                  state: Solver.symbols_solver_state(assigns),
                  start: JS.push("solve", value: %{target: "symbols"})
                }
              }
            />
        <% end %>

        <.final_output
          :if={@selected_step != :new and @selected_step != length(@nodes) and length(@nodes) > 1}
          puzzle={@puzzle}
          last_step={length(@nodes)}
          text={@final_output}
        />
      </div>
    </Layouts.app>
    """
  end
end
