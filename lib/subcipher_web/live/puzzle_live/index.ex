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
      guess_choice: nil,
      cipher: nil,
      input_kind: nil,
      input_kinds: []
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

  # ?cipher=TYPE: a cipher that starts from pictures (symbol substitution:
  # they are uploaded, so an account is needed), then the input it needs.
  # ?input=text|pictures picks among the cipher's input kinds
  # (Cipher.input_kinds/0), the first one by default. Other ciphers open on
  # their own page, without an account.
  @impl true
  def handle_params(params, _uri, socket) do
    case Steps.fetch_cipher(params["cipher"] || "") do
      {:ok, cipher} ->
        cond do
          not pictures?(cipher) ->
            socket |> push_navigate(to: ~p"/ciphers/#{cipher.type()}") |> wrap(:noreply)

          !socket.assigns.current_scope ->
            socket |> login_to_upload() |> wrap(:noreply)

          true ->
            socket |> assign_new_puzzle(cipher, params["input"]) |> wrap(:noreply)
        end

      :error ->
        socket |> assign_new_puzzle(nil, nil) |> wrap(:noreply)
    end
  end

  defp assign_new_puzzle(socket, cipher, input) do
    kinds = if cipher, do: Enum.map(cipher.input_kinds(), &to_string/1), else: []
    input = if input in kinds, do: input, else: List.first(kinds)

    # A guess chosen for this cipher: its text fills the form, its settings
    # are applied to the new puzzle.
    choice = socket.assigns.guess_choice
    choice = if cipher && choice && choice.type == cipher.type(), do: choice
    text = if choice, do: %{"input_text" => choice.text}, else: %{}

    assign(socket,
      cipher: cipher,
      input_kind: input,
      input_kinds: kinds,
      guess_choice: choice,
      text_form: to_form(Ciphers.change_text_puzzle(text))
    )
  end

  defp pictures?(cipher), do: :pictures in cipher.input_kinds()

  defp login_to_upload(socket) do
    socket
    |> put_flash(:error, "Log in to decode pictures of symbols.")
    |> push_navigate(to: ~p"/users/log-in")
  end

  # Creating and deleting need an account.
  @impl true
  def handle_event(event, _params, %{assigns: %{current_scope: nil}} = socket)
      when event in ~w(create_algorithm create_text delete) do
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

  def handle_event("toggle_guess_solution", %{"type" => type}, socket) do
    socket |> Guessing.toggle_reveal(type) |> wrap(:noreply)
  end

  # Opens the guessed cipher with the guessed text to decode, and the
  # settings of its guess (none for a hint: `hint` set). A cipher that
  # starts from pictures opens as a new puzzle instead (account needed).
  def handle_event("use_guess", %{"type" => type} = params, socket) do
    with {:ok, cipher} <- Steps.fetch_cipher(type) do
      guess = if params["hint"], do: nil, else: Guessing.find(socket, type)
      text = socket.assigns.guess_text
      label = guess && guess.label
      settings = if guess, do: guess.params, else: %{}

      cond do
        not pictures?(cipher) ->
          query = %{mode: "decode", text: text, params: url_params(settings)}

          socket
          |> put_guess_flash(label)
          |> push_navigate(to: ~p"/ciphers/#{type}?#{query}")

        !socket.assigns.current_scope ->
          login_to_upload(socket)

        true ->
          choice = %{type: type, text: text, params: settings, label: label}

          socket
          |> assign(guess_choice: choice)
          |> push_patch(to: ~p"/?cipher=#{type}&input=text")
      end
      |> wrap(:noreply)
    else
      :error -> wrap(socket, :noreply)
    end
  end

  def handle_event("choose_cipher", %{"type" => type}, socket) do
    case Steps.fetch_cipher(type) do
      {:ok, cipher} ->
        cond do
          not pictures?(cipher) -> push_navigate(socket, to: ~p"/ciphers/#{type}")
          !socket.assigns.current_scope -> login_to_upload(socket)
          true -> push_patch(socket, to: ~p"/?cipher=#{type}")
        end

      :error ->
        socket
    end
    |> wrap(:noreply)
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

  # Settings for a query string: "automatic" (nil) ones are left out.
  defp url_params(params), do: for({k, v} <- params, v != nil, into: %{}, do: {k, v})

  defp put_guess_flash(socket, nil), do: socket

  defp put_guess_flash(socket, label),
    do: put_flash(socket, :info, "Guessed settings applied: #{label}.")

  defp picture_ciphers, do: for(c <- Steps.ciphers(), pictures?(c), do: c.type())

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
              Pick a cipher to encode or decode with it right away: tune its settings, add
              steps (each taking the previous one's output), and save it as a puzzle when it's
              worth keeping.
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
            revealed={@guess_revealed}
            current_scope={@current_scope}
          />

          <div :if={!@cipher} id="choose-cipher" class="space-y-3">
            <h2 class="font-semibold">Know the cipher? Pick it.</h2>
            <.cipher_grid
              id_prefix="new-cipher-"
              event="choose_cipher"
              locked={if @current_scope, do: [], else: picture_ciphers()}
            />
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
          public_puzzles={@public_puzzles}
          algorithms={@algorithms}
          public_algorithms={@public_algorithms}
          new_algorithm={@new_algorithm}
        />
      </section>
    </Layouts.app>
    """
  end
end
