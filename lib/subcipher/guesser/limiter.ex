defmodule Subcipher.Guesser.Limiter do
  @moduledoc """
  Limits how many deep guesses (`Subcipher.Guesser.deep/3`, CPU-heavy) run
  at once on the server. A process holds a slot while it runs; the slot is
  freed when it finishes or dies (cancelled guesses are killed). When every
  slot is taken, `run/1` doesn't wait: it returns `{:error, :busy}`.

  The number of slots is `config :subcipher, #{inspect(__MODULE__)}, max:`
  (default: the number of schedulers).
  """
  use GenServer

  def start_link(opts \\ []),
    do: GenServer.start_link(__MODULE__, opts, name: Keyword.get(opts, :name, __MODULE__))

  @doc "Runs `fun` in a slot of `limiter`: `{:ok, result}`, or `{:error, :busy}`."
  def run(fun, limiter \\ __MODULE__) do
    case GenServer.call(limiter, :acquire) do
      :ok ->
        try do
          {:ok, fun.()}
        after
          GenServer.cast(limiter, {:release, self()})
        end

      :busy ->
        {:error, :busy}
    end
  end

  @impl true
  def init(opts) do
    config = Application.get_env(:subcipher, __MODULE__, [])
    max = opts[:max] || config[:max] || System.schedulers_online()
    {:ok, %{max: max, holders: %{}}}
  end

  @impl true
  def handle_call(:acquire, {pid, _}, %{max: max, holders: holders} = state) do
    if map_size(holders) < max do
      {:reply, :ok, %{state | holders: Map.put(holders, pid, Process.monitor(pid))}}
    else
      {:reply, :busy, state}
    end
  end

  @impl true
  def handle_cast({:release, pid}, state), do: {:noreply, release(state, pid)}

  @impl true
  def handle_info({:DOWN, _ref, :process, pid, _reason}, state),
    do: {:noreply, release(state, pid)}

  defp release(%{holders: holders} = state, pid) do
    case Map.pop(holders, pid) do
      {nil, _} ->
        state

      {ref, holders} ->
        Process.demonitor(ref, [:flush])
        %{state | holders: holders}
    end
  end
end
