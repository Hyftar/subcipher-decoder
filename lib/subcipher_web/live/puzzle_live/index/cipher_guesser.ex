defmodule SubcipherWeb.PuzzleLive.Index.CipherGuesser do
  @moduledoc """
  "Which cipher is it?" guessed from the cipher text (`Subcipher.Guesser`):
  the ciphers ranked by how English their best result reads, each one ready
  to start decoding with. Quick results come first; the solvers' results
  (the deep pass, `SubcipherWeb.PuzzleLive.Index.Guessing`) join the ranking
  as they arrive.
  """
  use SubcipherWeb, :html

  alias Subcipher.Guesser

  attr :form, :any, required: true, doc: "the guess form (`text`)"
  attr :status, :any, required: true, doc: "nil, :loading, :ready or {:error, reason}"
  attr :result, :map, default: nil, doc: "`Guesser.result/2`"
  attr :pending, :list, default: [], doc: "ciphers whose solver is still running"
  attr :note, :atom, default: nil, doc: "why there is no deep pass: :login or :busy"

  attr :revealed, :any,
    default: MapSet.new(),
    doc: "types of the ciphers whose solution is shown (hidden by default)"

  attr :current_scope, :any, required: true

  def cipher_guesser(assigns) do
    ~H"""
    <div
      id="cipher-guesser"
      class="rounded-2xl border border-base-300 bg-gradient-to-br from-secondary/5 via-base-100 to-base-100 p-5 space-y-4"
    >
      <div class="flex items-start gap-3">
        <div class="grid place-items-center size-10 shrink-0 rounded-xl bg-secondary/15 text-secondary">
          <.icon name="hero-sparkles" class="size-5" />
        </div>
        <div class="space-y-0.5">
          <h2 class="font-semibold">Not sure? Let us guess</h2>
          <p class="text-sm text-base-content/60">
            Paste the cipher text: every cipher tries its likeliest keys, and the one whose
            result reads most like English wins.
          </p>
        </div>
      </div>

      <.form for={@form} id="guess-form" phx-submit="guess" class="space-y-2">
        <.input
          field={@form[:text]}
          type="textarea"
          rows="3"
          placeholder="Wkh vhfuhw lv xqghu wkh rog rdn wuhh"
          class="w-full textarea font-mono leading-relaxed"
        />
        <div class="flex justify-end">
          <button
            type="submit"
            id="guess-button"
            class="btn btn-secondary transition hover:-translate-y-0.5"
            phx-disable-with="Guessing…"
          >
            <.icon name="hero-magnifying-glass" class="size-4" /> Guess the cipher
          </button>
        </div>
      </.form>

      <div
        :if={@status == :loading}
        id="guess-loading"
        class="flex items-center gap-2 text-sm text-base-content/60"
      >
        <span class="loading loading-spinner loading-sm"></span> Trying every cipher…
      </div>

      <p
        :if={match?({:error, _}, @status)}
        id="guess-error"
        class="text-sm text-warning flex items-center gap-2"
      >
        <.icon name="hero-exclamation-triangle" class="size-4" /> {error_message(@status)}
      </p>

      <.deep_status :if={@status == :ready} pending={@pending} note={@note} />

      <.results
        :if={@status == :ready && @result}
        result={@result}
        searching={@pending != []}
        revealed={@revealed}
        current_scope={@current_scope}
      />
    </div>
    """
  end

  attr :pending, :list, required: true
  attr :note, :atom, required: true

  # What the deep pass is doing, or why it doesn't run.
  defp deep_status(assigns) do
    ~H"""
    <div
      :if={@pending != []}
      id="guess-deep-pending"
      class="flex items-center gap-2 rounded-lg bg-base-200/60 px-3 py-2 text-sm text-base-content/70"
    >
      <span class="loading loading-dots loading-sm text-secondary"></span>
      <span>
        Searching harder with the solvers: {Enum.map_join(@pending, ", ", & &1.name())}…
        <span class="text-base-content/50">(results join the ranking as they come)</span>
      </span>
    </div>
    <p
      :if={@note == :login}
      id="guess-deep-login"
      class="flex items-center gap-2 text-sm text-base-content/60"
    >
      <.icon name="hero-lock-closed" class="size-4 shrink-0" />
      <span>
        <.link navigate={~p"/users/log-in"} class="link link-hover font-medium">Log in</.link>
        to search harder: solvers for shuffled alphabets, keywords and Vigenère keys.
      </span>
    </p>
    <p
      :if={@note == :busy}
      id="guess-deep-busy"
      class="flex items-center gap-2 text-sm text-warning"
    >
      <.icon name="hero-clock" class="size-4 shrink-0" />
      The server is busy: some solvers were skipped. Guess again in a moment.
    </p>
    """
  end

  attr :result, :map, required: true
  attr :searching, :boolean, default: false, doc: "solvers still running"
  attr :revealed, :any, required: true
  attr :current_scope, :any, required: true

  defp results(assigns) do
    guesses =
      assigns.result.guesses
      |> Enum.with_index()
      |> Enum.map(fn {guess, index} ->
        readable? = Guesser.readable?(guess)

        Map.merge(guess, %{
          index: index,
          readable?: readable?,
          winner: index == 0 and readable?,
          revealed?: MapSet.member?(assigns.revealed, guess.cipher.type())
        })
      end)

    assigns = assign(assigns, guesses: guesses, readable?: Enum.any?(guesses, & &1.readable?))

    ~H"""
    <div id="guess-results" class="space-y-3">
      <p
        :if={@result.plain}
        id="guess-plain"
        class="text-sm rounded-lg bg-info/10 text-info-content/80 px-3 py-2 flex gap-2"
      >
        <.icon name="hero-information-circle" class="size-5 shrink-0 text-info" />
        This text already reads like English: maybe it isn't encoded, or only its letters
        were shuffled (anagram).
      </p>

      <div
        :if={!@readable?}
        id="guess-no-match"
        class="rounded-xl border border-dashed border-base-300 p-4 space-y-2"
      >
        <p class="text-sm font-medium flex items-center gap-2">
          <.icon name="hero-question-mark-circle" class="size-5 text-base-content/40" />
          {if @searching,
            do: "Nothing reads like English yet.",
            else: "No cipher's result reads like English."}
        </p>
        <div :if={@result.hint} id="guess-hint" class="text-sm text-base-content/70 space-y-2">
          <p>
            <span class="font-medium text-base-content">Most likely: {@result.hint.cipher.name()}.</span>
            {@result.hint.reason}
          </p>
          <.use_button
            id="guess-hint-use"
            type={@result.hint.cipher.type()}
            hint
            current_scope={@current_scope}
            primary={false}
          />
        </div>
      </div>

      <ol id="guess-list" class="space-y-2">
        <li
          :for={guess <- @guesses}
          id={"guess-#{guess.cipher.type()}"}
          class={[
            "group rounded-xl border p-3 transition",
            if(guess.winner,
              do: "border-secondary/50 bg-secondary/5 shadow-sm",
              else: "border-base-300 bg-base-100 hover:border-base-content/20"
            ),
            !guess.readable? && "opacity-70 hover:opacity-100"
          ]}
        >
          <div class="flex items-start gap-3">
            <span class={[
              "grid place-items-center size-6 shrink-0 rounded-full text-xs font-semibold",
              if(guess.winner,
                do: "bg-secondary text-secondary-content",
                else: "bg-base-200 text-base-content/60"
              )
            ]}>
              {guess.index + 1}
            </span>
            <div class="flex-1 min-w-0 space-y-1.5">
              <div class="flex flex-wrap items-baseline justify-between gap-x-3 gap-y-1">
                <p class="font-semibold">
                  {guess.cipher.name()}
                  <span
                    :if={guess.revealed?}
                    id={"guess-label-#{guess.cipher.type()}"}
                    class="font-normal text-sm text-base-content/60"
                  >
                    · {guess.label}
                  </span>
                  <span
                    :if={guess.deep}
                    id={"guess-solver-#{guess.cipher.type()}"}
                    class="ml-1 inline-flex items-center gap-1 rounded-full bg-secondary/15 px-2 py-0.5 align-middle text-xs font-medium text-secondary"
                    title="Found by the solver (deep search)"
                  >
                    <.icon name="hero-cpu-chip" class="size-3" /> Solver
                  </span>
                </p>
                <.fit_meter fit={guess.fit} />
              </div>
              <p
                :if={guess.recognized}
                id={"guess-recognized-#{guess.cipher.type()}"}
                class="inline-flex items-start gap-1.5 rounded-md bg-success/10 px-2 py-1 text-xs text-base-content/80"
              >
                <.icon name="hero-check-badge" class="size-4 shrink-0 text-success" />
                <span><span class="font-medium">Format recognized.</span> {guess.recognized}</span>
              </p>
              <p
                :if={guess.revealed?}
                id={"guess-preview-#{guess.cipher.type()}"}
                class="font-mono text-sm break-words bg-base-200/60 rounded-md px-2 py-1"
              >
                {guess.preview}
              </p>
              <p
                :if={!guess.revealed?}
                class="flex items-center gap-1.5 rounded-md border border-dashed border-base-300 px-2 py-1 text-xs text-base-content/50"
              >
                <.icon name="hero-eye-slash" class="size-4 shrink-0" />
                Solution and key hidden so they don't spoil the puzzle.
              </p>
              <p :if={guess.same_as} class="text-xs text-base-content/50">
                Same result as {guess.same_as.name()}, a simpler explanation.
              </p>
              <%!-- The reason can name the key or words of the result. --%>
              <p
                :if={!guess.same_as and guess.revealed?}
                id={"guess-reason-#{guess.cipher.type()}"}
                class="text-xs text-base-content/60"
              >
                {guess.reason}
              </p>
            </div>
          </div>
          <div class="flex flex-wrap items-center justify-between gap-2 mt-2">
            <.reveal_switch type={guess.cipher.type()} revealed={guess.revealed?} />
            <.use_button
              id={"guess-use-#{guess.cipher.type()}"}
              type={guess.cipher.type()}
              current_scope={@current_scope}
              primary={guess.winner}
            />
          </div>
        </li>
      </ol>
    </div>
    """
  end

  attr :fit, :float, required: true, doc: "0..1, nil when too short to score"

  defp fit_meter(%{fit: nil} = assigns) do
    ~H"""
    <span class="text-xs text-base-content/50" title="Fewer than 4 letters: too short to score">
      Too short to score
    </span>
    """
  end

  defp fit_meter(assigns) do
    assigns = assign(assigns, percent: round(assigns.fit * 100))

    ~H"""
    <span class="flex items-center gap-2 text-xs text-base-content/60" title="How English it reads">
      <span class="relative h-1.5 w-20 overflow-hidden rounded-full bg-base-300">
        <span
          class={[
            "absolute inset-y-0 left-0 rounded-full transition-all duration-500",
            cond do
              @fit >= Guesser.readable() -> "bg-success"
              @fit >= 0.4 -> "bg-warning"
              true -> "bg-error/70"
            end
          ]}
          style={"width: #{@percent}%"}
        ></span>
      </span>
      {fit_label(@fit)}
    </span>
    """
  end

  attr :type, :string, required: true
  attr :revealed, :boolean, required: true

  # Shows or hides a guess's solution.
  defp reveal_switch(assigns) do
    ~H"""
    <button
      type="button"
      role="switch"
      id={"guess-reveal-#{@type}"}
      aria-checked={to_string(@revealed)}
      phx-click="toggle_guess_solution"
      phx-value-type={@type}
      class="group/switch inline-flex items-center gap-2 rounded-full py-1 pr-2 text-xs font-medium text-base-content/60 cursor-pointer select-none transition-colors hover:text-base-content focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-secondary/50"
    >
      <span class={[
        "relative inline-flex h-5 w-9 shrink-0 items-center rounded-full transition-colors duration-200",
        if(@revealed,
          do: "bg-secondary",
          else: "bg-base-300 group-hover/switch:bg-base-content/25"
        )
      ]}>
        <span class={[
          "inline-block size-4 rounded-full bg-base-100 shadow-sm transition-transform duration-200",
          if(@revealed, do: "translate-x-4.5", else: "translate-x-0.5")
        ]}></span>
      </span>
      Show solution
    </button>
    """
  end

  attr :id, :string, required: true
  attr :type, :string, required: true
  attr :hint, :boolean, default: false, doc: "a hint: start without settings"
  attr :current_scope, :any, required: true
  attr :primary, :boolean, default: false

  defp use_button(assigns) do
    ~H"""
    <button
      type="button"
      id={@id}
      phx-click="use_guess"
      phx-value-type={@type}
      phx-value-hint={@hint && "true"}
      class={[
        "btn btn-sm transition group-hover:translate-x-0.5",
        if(@primary, do: "btn-secondary", else: "btn-ghost")
      ]}
    >
      {if @current_scope, do: "Decode with this", else: "Log in to decode"}
      <.icon name="hero-arrow-right" class="size-4" />
    </button>
    """
  end

  defp fit_label(fit) do
    cond do
      fit >= Guesser.readable() -> "Reads like English"
      fit >= 0.4 -> "Partly English"
      true -> "Not English"
    end
  end

  defp error_message({:error, :too_short}), do: "Too short to guess: paste at least 8 characters."

  defp error_message({:error, :too_long}),
    do: "Too long to guess: paste at most 5,000 characters."

  defp error_message(_), do: "Something went wrong while guessing. Try again."
end
