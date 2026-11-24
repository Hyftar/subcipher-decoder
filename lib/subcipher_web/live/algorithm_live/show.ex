defmodule SubcipherWeb.AlgorithmLive.Show do
  @moduledoc """
  An algorithm: encode or decode any text with its steps, showing the text
  after each step; its steps can be edited.

  Events are handled by `Events.Input` (what is encoded or decoded),
  `Events.Image` (the options of the symbol image) and `Events.Editor`
  (changes to the algorithm: owner only).
  """
  use SubcipherWeb, :live_view

  alias Subcipher.Algorithms
  alias Subcipher.Accounts.Scope

  alias SubcipherWeb.AlgorithmLive.{Assigns, Events}
  alias SubcipherWeb.AlgorithmLive.Steps.{EditorSteps, Summaries}

  import SubcipherWeb.AlgorithmLive.{Header, Input, ModeSwitch, Trace}
  import SubcipherWeb.AlgorithmLive.Steps.{Editor, Overview}

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    case Algorithms.get_algorithm_for(socket.assigns.current_scope, id) do
      nil ->
        socket
        |> put_flash(:error, "This algorithm doesn't exist, or it is private.")
        |> push_navigate(to: ~p"/")
        |> wrap(:ok)

      algorithm ->
        socket
        |> init(algorithm)
        |> wrap(:ok)
    end
  end

  defp init(socket, algorithm) do
    assign(socket,
      # Only the owner edits it; others use a public algorithm as it is.
      owner?: Scope.owner?(socket.assigns.current_scope, algorithm),
      page_title: algorithm.title,
      algorithm: algorithm,
      steps: Summaries.describe(algorithm),
      # Editing the steps; invalid settings forms being edited, by step index.
      editing: false,
      step_forms: %{},
      mode: "encode",
      # What the user typed, per mode (kept when switching).
      texts: %{"encode" => "", "decode" => ""},
      # Pictures, decode: the symbols composed with the keyboard.
      symbols: [],
      # Pictures: the options of the symbol image (encoded output, or the
      # cipher symbols when decoding). Its style is "original" (the crops as
      # they are) or "mask" (their black and white pass, in the ink colour);
      # colours are "auto" (detected in the glyphs, reported by the
      # .SymbolImage hook) or chosen by hand.
      image: %{
        style: "original",
        align: "center",
        background: "auto",
        ink: "auto",
        transparent: false
      },
      detected: %{background: nil, ink: nil}
    )
  end

  @impl true
  def handle_params(params, _uri, socket) do
    mode = if params["mode"] in ~w(encode decode), do: params["mode"], else: "encode"
    # ?edit=true opens the editor (a new algorithm starts there).
    editing = socket.assigns.owner? and (socket.assigns.editing or params["edit"] == "true")

    socket
    |> assign(mode: mode, editing: editing)
    |> Assigns.assign_trace()
    |> wrap(:noreply)
  end

  @input_events ~w(input add_symbol add_char backspace clear)
  @image_events ~w(image_options image_align image_style image_auto image_transparent detected_colours)
  # Changing the algorithm is for its owner; anyone who can see it can use it.
  @owner_events ~w(toggle_edit rename add_step change_step_type update_step move_step delete_step delete toggle_public)

  @impl true
  def handle_event(event, _params, %{assigns: %{owner?: false}} = socket)
      when event in @owner_events do
    socket
    |> put_flash(:error, "This algorithm belongs to someone else.")
    |> wrap(:noreply)
  end

  def handle_event(event, params, socket) when event in @input_events,
    do: Events.Input.handle_event(event, params, socket)

  def handle_event(event, params, socket) when event in @image_events,
    do: Events.Image.handle_event(event, params, socket)

  def handle_event(event, params, socket) when event in @owner_events,
    do: Events.Editor.handle_event(event, params, socket)

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div id="algorithm" class="space-y-6">
        <.algorithm_header algorithm={@algorithm} editing={@editing} owner={@owner?} />
        <.steps_editor :if={@editing} algorithm={@algorithm} steps={EditorSteps.build(assigns)} />
        <.steps_overview :if={!@editing} steps={@steps} owner={@owner?} />
        <.mode_switch algorithm={@algorithm} mode={@mode} />
        <.algorithm_input
          algorithm={@algorithm}
          mode={@mode}
          text={@texts[@mode]}
          symbols={@symbols}
        />
        <.trace
          algorithm={@algorithm}
          mode={@mode}
          trace={@trace}
          image={@image}
          detected={@detected}
        />
      </div>
    </Layouts.app>
    """
  end
end
