defmodule SubcipherWeb.PuzzleLive.Index.Guessing do
  @moduledoc """
  The cipher guesser of the home page (`Subcipher.Guesser`), in two passes
  running in the background:

    * the quick pass (suggestions), shown as soon as it's done;
    * the deep pass (solvers), one task per cipher, each result merged
      into the ranking as it arrives. Only for logged-in users (it is
      CPU-heavy), at most `Subcipher.Guesser.Limiter` of them at once on
      the server, each cut after `config :subcipher, :guesser_deep_timeout`
      ms (default 30 s).

  A new guess cancels the one still running; results of an older guess
  (`guess_run`) are ignored.

  Assigns: `guess_form`, `guess_text`, `guess_run`, `guess_status` (nil,
  `:loading`, `:ready` or `{:error, reason}`), `guess_candidates`,
  `guess_result` (`Subcipher.Guesser.result/2`), `guess_pending` (ciphers
  whose deep pass is running), `guess_note` (nil, `:login` or `:busy`).
  """

  import Phoenix.Component, only: [assign: 2, to_form: 2]
  import Phoenix.LiveView, only: [start_async: 3, cancel_async: 2]

  alias Subcipher.Guesser
  alias Subcipher.Guesser.Limiter

  def mount(socket) do
    assign(socket,
      guess_form: to_form(%{"text" => ""}, as: :guess),
      guess_text: nil,
      guess_run: 0,
      guess_status: nil,
      guess_candidates: [],
      guess_result: nil,
      guess_pending: [],
      guess_note: nil
    )
  end

  @doc "Starts guessing `text`, cancelling the guess still running."
  def start(socket, text) do
    run = socket.assigns.guess_run + 1

    socket
    |> cancel()
    |> assign(
      guess_form: to_form(%{"text" => text}, as: :guess),
      guess_text: text,
      guess_run: run,
      guess_status: :loading,
      guess_candidates: [],
      guess_result: nil,
      guess_pending: [],
      guess_note: nil
    )
    |> start_async({:guess_quick, run}, fn -> Guesser.quick(text) end)
    |> start_deep(text, run)
  end

  defp start_deep(socket, text, run) do
    ciphers = Guesser.deep_ciphers(text)

    cond do
      ciphers == [] ->
        socket

      socket.assigns.current_scope == nil ->
        assign(socket, guess_note: :login)

      true ->
        timeout = Application.get_env(:subcipher, :guesser_deep_timeout, 30_000)

        ciphers
        |> Enum.reduce(socket, fn cipher, socket ->
          start_async(socket, {:guess_deep, run, cipher}, fn ->
            Limiter.run(fn -> Guesser.deep(text, cipher, timeout) end)
          end)
        end)
        |> assign(guess_pending: ciphers)
    end
  end

  defp cancel(%{assigns: %{guess_run: run}} = socket) do
    socket =
      if socket.assigns.guess_status == :loading,
        do: cancel_async(socket, {:guess_quick, run}),
        else: socket

    Enum.reduce(socket.assigns.guess_pending, socket, fn cipher, socket ->
      cancel_async(socket, {:guess_deep, run, cipher})
    end)
  end

  @doc "Handles the end of a pass (`handle_async/3`)."
  def handle_async({_, run}, _result, %{assigns: %{guess_run: current}} = socket)
      when run != current,
      do: socket

  def handle_async({_, run, _}, _result, %{assigns: %{guess_run: current}} = socket)
      when run != current,
      do: socket

  def handle_async({:guess_quick, _}, {:ok, {:ok, candidates}}, socket) do
    socket
    |> assign(guess_status: :ready)
    |> add(candidates)
  end

  def handle_async({:guess_quick, _}, {:ok, {:error, reason}}, socket) do
    socket
    |> cancel()
    |> assign(guess_status: {:error, reason}, guess_pending: [], guess_note: nil)
  end

  def handle_async({:guess_quick, _}, {:exit, _reason}, socket) do
    socket |> cancel() |> assign(guess_status: {:error, :failed}, guess_pending: [])
  end

  def handle_async({:guess_deep, _, cipher}, result, socket) do
    socket = assign(socket, guess_pending: List.delete(socket.assigns.guess_pending, cipher))

    case result do
      {:ok, {:ok, candidate}} -> add(socket, List.wrap(candidate))
      {:ok, {:error, :busy}} -> assign(socket, guess_note: :busy)
      _ -> socket
    end
  end

  defp add(socket, candidates) do
    candidates = Enum.reduce(candidates, socket.assigns.guess_candidates, &Guesser.merge(&2, &1))

    assign(socket,
      guess_candidates: candidates,
      guess_result: Guesser.result(socket.assigns.guess_text, candidates)
    )
  end

  @doc """
  The guess of cipher `type` in the current ranking (to start a puzzle
  with its settings), or nil.
  """
  def find(%{assigns: %{guess_result: %{guesses: guesses}}}, type),
    do: Enum.find(guesses, &(&1.cipher.type() == type))

  def find(_socket, _type), do: nil
end
