defmodule SubcipherWeb.PuzzleLive.Index do
  use SubcipherWeb, :live_view

  alias Subcipher.{Algorithms, Ciphers}
  alias Subcipher.Accounts.Scope
  alias Subcipher.Steps

  import SubcipherWeb.Components.CipherGrid
  import SubcipherWeb.PuzzleLive.Index.{CipherGuesser, Library, NewPuzzle, SignUpPrompt}

  alias SubcipherWeb.PuzzleLive.Index.Guessing

  @impl true
  def mount(_params, _session, socket) do
    socket
    |> assign(
      page_title: "Puzzles",
      text_form: to_form(Ciphers.change_text_puzzle()),
      new_algorithm: false,
      guess_choice: nil
    )
    |> Guessing.mount()
    |> assign_lists()
    |> wrap(:ok)
  end

  # The user's puzzles and algorithms, and the public ones of other users.
  defp assign_lists(socket) do
    scope = socket.assigns.current_scope

    socket
    |> assign(
      puzzles: Ciphers.list_puzzles(scope),
      algorithms: Algorithms.list_algorithms(scope),
      public_puzzles: Ciphers.list_public_puzzles(scope),
      public_algorithms: Algorithms.list_public_algorithms(scope)
    )
  end

  # ?cipher=TYPE: the cipher of the new puzzle (its first step), then the
  # input it needs. ?input=text|pictures picks among the cipher's input
  # kinds (Cipher.input_kinds/0), the first one by default.
  @impl true
  def handle_params(params, _uri, socket) do
    cipher =
      case Steps.fetch_cipher(params["cipher"] || "") do
        {:ok, cipher} -> cipher
        :error -> nil
      end

    kinds = if cipher, do: Enum.map(cipher.input_kinds(), &to_string/1), else: []
    input = if params["input"] in kinds, do: params["input"], else: List.first(kinds)

    # A guess chosen for this cipher: its text fills the form, its settings
    # are applied to the new puzzle.
    choice = socket.assigns.guess_choice
    choice = if cipher && choice && choice.type == cipher.type(), do: choice
    text = if choice, do: %{"input_text" => choice.text}, else: %{}

    socket
    |> assign(
      cipher: cipher,
      input_kind: input,
      input_kinds: kinds,
      guess_choice: choice,
      text_form: to_form(Ciphers.change_text_puzzle(text))
    )
    |> wrap(:noreply)
  end

  # Creating and deleting need an account.
  @impl true
  def handle_event(event, _params, %{assigns: %{current_scope: nil}} = socket)
      when event in ~w(create_algorithm create_text delete use_guess) do
    socket
    |> put_flash(:error, "Log in to create puzzles and algorithms.")
    |> push_navigate(to: ~p"/users/log-in")
    |> wrap(:noreply)
  end

  def handle_event("toggle_new_algorithm", _params, socket) do
    socket |> update(:new_algorithm, &(!&1)) |> wrap(:noreply)
  end

  # A new algorithm opens in its editor.
  def handle_event("create_algorithm", %{"type" => type}, socket) do
    case Algorithms.create_algorithm(socket.assigns.current_scope, type) do
      {:ok, algorithm} ->
        socket |> push_navigate(to: ~p"/algorithms/#{algorithm}?edit=true") |> wrap(:noreply)

      {:error, _} ->
        socket
        |> put_flash(:error, "This cipher can't be used in an algorithm.")
        |> wrap(:noreply)
    end
  end

  def handle_event("guess", %{"guess" => %{"text" => text}}, socket) do
    socket |> Guessing.start(text) |> wrap(:noreply)
  end

  # Starts a new puzzle with the guessed cipher, prefilled with the guessed
  # text, with the settings of its guess (none for a hint: `hint` set).
  def handle_event("use_guess", %{"type" => type} = params, socket) do
    guess = if params["hint"], do: nil, else: Guessing.find(socket, type)

    choice = %{
      type: type,
      text: socket.assigns.guess_text,
      params: if(guess, do: guess.params, else: %{}),
      label: guess && guess.label
    }

    socket
    |> assign(guess_choice: choice)
    |> push_patch(to: ~p"/?cipher=#{type}&input=text")
    |> wrap(:noreply)
  end

  def handle_event("choose_cipher", %{"type" => type}, socket) do
    socket |> push_patch(to: ~p"/?cipher=#{type}") |> wrap(:noreply)
  end

  def handle_event("validate_text", %{"puzzle" => params}, socket) do
    form = params |> Ciphers.change_text_puzzle() |> Map.put(:action, :validate) |> to_form()
    socket |> assign(text_form: form) |> wrap(:noreply)
  end

  def handle_event("create_text", %{"puzzle" => params}, socket) do
    case Ciphers.create_text_puzzle(
           socket.assigns.current_scope,
           params,
           socket.assigns.cipher.type(),
           guess_params(socket.assigns.guess_choice)
         ) do
      {:ok, puzzle} ->
        socket |> push_navigate(to: ~p"/puzzles/#{puzzle}") |> wrap(:noreply)

      {:error, %Ecto.Changeset{} = changeset} ->
        socket |> assign(text_form: to_form(changeset)) |> wrap(:noreply)

      {:error, _} ->
        socket |> put_flash(:error, "Could not create the puzzle.") |> wrap(:noreply)
    end
  end

  def handle_event("delete", %{"id" => id}, socket) do
    puzzle = Ciphers.get_puzzle(id)

    if puzzle && Scope.owner?(socket.assigns.current_scope, puzzle) do
      {:ok, _} = Ciphers.delete_puzzle(puzzle)
      socket |> put_flash(:info, "Puzzle deleted.") |> assign_lists() |> wrap(:noreply)
    else
      wrap(socket, :noreply)
    end
  end

  @impl true
  def handle_async(name, result, socket),
    do: name |> Guessing.handle_async(result, socket) |> wrap(:noreply)

  defp guess_params(%{params: params}), do: params
  defp guess_params(nil), do: %{}

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <section class="grid gap-8 lg:grid-cols-[minmax(0,3fr)_minmax(0,2fr)]">
        <div class="space-y-4">
          <div>
            <h1 class="text-2xl font-bold tracking-tight">Crack a cipher</h1>
            <p class="text-base-content/70 mt-1">
              Choose the cipher, give it the cipher text (or pictures of its symbols), then
              decode it step by step: more steps can be added, each taking the previous one's
              output.
            </p>
          </div>
          <.sign_up_prompt :if={!@current_scope} />

          <.cipher_guesser
            :if={!@cipher}
            form={@guess_form}
            status={@guess_status}
            result={@guess_result}
            pending={@guess_pending}
            note={@guess_note}
            current_scope={@current_scope}
          />

          <div :if={@current_scope && !@cipher} id="choose-cipher" class="space-y-3">
            <h2 class="font-semibold">Know the cipher? Pick it</h2>
            <.cipher_grid id_prefix="new-cipher-" event="choose_cipher" />
          </div>
          <.new_puzzle
            :if={@current_scope && @cipher}
            cipher={@cipher}
            input_kind={@input_kind}
            input_kinds={@input_kinds}
            text_form={@text_form}
            guess_choice={@guess_choice}
            current_scope={@current_scope}
          />
        </div>

        <.library
          current_scope={@current_scope}
          puzzles={@puzzles}
          algorithms={@algorithms}
          public_puzzles={@public_puzzles}
          public_algorithms={@public_algorithms}
          new_algorithm={@new_algorithm}
        />
      </section>
    </Layouts.app>
    """
  end
end
