defmodule SubcipherWeb.AlgorithmLive.Show do
  @moduledoc """
  An algorithm: encode or decode any text with its steps, showing the text
  after each step; its steps can be edited.

  A cipher (`/ciphers/:type`, live action `:cipher`) opens here too, as an
  unsaved algorithm (a draft, `Subcipher.Algorithms.new_draft/2`) anyone can
  edit and use without an account; a logged-in user can save it as a
  puzzle. `?text=` (cipher text to decode) and `?params=` (settings of its
  step) prefill it, e.g. from a guess. Ciphers that start from pictures
  need an account and their own page (uploads): they aren't opened here.

  Events are handled by `Events.Input` (what is encoded or decoded),
  `Events.Image` (the options of the symbol image), `Events.Editor`
  (changes to the algorithm: owner, or anyone for a draft) and `Events.Save`
  (saving a draft).
  """
  use SubcipherWeb, :live_view

  alias Subcipher.{Algorithms, Steps}
  alias Subcipher.Accounts.Scope
  alias Subcipher.Algorithms.Algorithm

  alias SubcipherWeb.AlgorithmLive.{Assigns, Events}
  alias SubcipherWeb.AlgorithmLive.Steps.{EditorSteps, Summaries}

  import SubcipherWeb.AlgorithmLive.{Header, Input, ModeSwitch, SavePanel, Trace}
  import SubcipherWeb.AlgorithmLive.Steps.{Editor, Overview}

  @impl true
  def mount(%{"type" => type} = params, _session, socket) do
    scope = socket.assigns.current_scope

    case Steps.fetch_cipher(type) do
      {:ok, cipher} ->
        cond do
          :pictures not in cipher.input_kinds() ->
            {:ok, draft} = Algorithms.new_draft(type, map_param(params["params"]))

            socket
            |> init(draft, ~p"/ciphers/#{type}")
            |> assign(texts: %{"encode" => "", "decode" => text_param(params["text"])})
            |> wrap(:ok)

          scope ->
            socket |> push_navigate(to: ~p"/?cipher=#{type}") |> wrap(:ok)

          true ->
            socket
            |> put_flash(:error, "Log in to decode pictures of symbols.")
            |> push_navigate(to: ~p"/users/log-in")
            |> wrap(:ok)
        end

      :error ->
        socket
        |> put_flash(:error, "This cipher doesn't exist.")
        |> push_navigate(to: ~p"/")
        |> wrap(:ok)
    end
  end

  def mount(%{"id" => id}, _session, socket) do
    case Algorithms.get_algorithm_for(socket.assigns.current_scope, id) do
      nil ->
        socket
        |> put_flash(:error, "This algorithm doesn't exist, or it is private.")
        |> push_navigate(to: ~p"/")
        |> wrap(:ok)

      algorithm ->
        socket
        |> init(algorithm, ~p"/algorithms/#{algorithm}")
        |> wrap(:ok)
    end
  end

  defp map_param(params) when is_map(params), do: params
  defp map_param(_), do: %{}

  defp text_param(text) when is_binary(text), do: text
  defp text_param(_), do: ""

  defp init(socket, algorithm, path) do
    draft? = Algorithm.draft?(algorithm)

    assign(socket,
      # A draft is everyone's to change: it is only in this page.
      draft?: draft?,
      # Only the owner edits it; others use a public algorithm as it is.
      owner?: draft? or Scope.owner?(socket.assigns.current_scope, algorithm),
      # The page's path (the mode is patched onto it).
      path: path,
      page_title: algorithm.title,
      algorithm: algorithm,
      steps: Summaries.describe(algorithm),
      # Editing the steps (a draft starts there); invalid settings forms
      # being edited, by step index.
      editing: draft?,
      step_forms: %{},
      mode: default_mode(draft?),
      # What the user typed, per mode (kept when switching).
      texts: %{"encode" => "", "decode" => ""},
      # A draft: the title it is saved with, as a puzzle.
      save_form: to_form(%{"title" => algorithm.title}, as: :puzzle),
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

  # A cipher is mostly opened to crack a cipher text; an algorithm, to
  # write messages.
  defp default_mode(true), do: "decode"
  defp default_mode(false), do: "encode"

  @impl true
  def handle_params(params, _uri, socket) do
    mode =
      if params["mode"] in ~w(encode decode),
        do: params["mode"],
        else: default_mode(socket.assigns.draft?)

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
  # A draft isn't saved: it can't be renamed (its title is chosen when
  # saving it), deleted or shared.
  @saved_events ~w(rename delete toggle_public)
  @save_events ~w(validate_save save_puzzle)

  @impl true
  def handle_event(event, _params, %{assigns: %{owner?: false}} = socket)
      when event in @owner_events do
    socket
    |> put_flash(:error, "This algorithm belongs to someone else.")
    |> wrap(:noreply)
  end

  def handle_event(event, _params, %{assigns: %{draft?: true}} = socket)
      when event in @saved_events,
      do: wrap(socket, :noreply)

  def handle_event(event, _params, %{assigns: %{draft?: false}} = socket)
      when event in @save_events,
      do: wrap(socket, :noreply)

  def handle_event(event, params, socket) when event in @input_events,
    do: Events.Input.handle_event(event, params, socket)

  def handle_event(event, params, socket) when event in @image_events,
    do: Events.Image.handle_event(event, params, socket)

  def handle_event(event, params, socket) when event in @owner_events,
    do: Events.Editor.handle_event(event, params, socket)

  def handle_event(event, params, socket) when event in @save_events,
    do: Events.Save.handle_event(event, params, socket)

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div id="algorithm" class="space-y-6">
        <.algorithm_header
          algorithm={@algorithm}
          editing={@editing}
          owner={@owner?}
          draft={@draft?}
          current_scope={@current_scope}
        />
        <.steps_editor :if={@editing} algorithm={@algorithm} steps={EditorSteps.build(assigns)} />
        <.steps_overview :if={!@editing} steps={@steps} owner={@owner?} />
        <.mode_switch path={@path} mode={@mode} />
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
        <.save_panel
          :if={@draft?}
          current_scope={@current_scope}
          form={@save_form}
          mode={@mode}
          cipher_text={Events.Save.cipher_text(assigns)}
        />
      </div>
    </Layouts.app>
    """
  end
end
