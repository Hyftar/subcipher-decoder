defmodule SubcipherWeb.AlgorithmLive.Assigns do
  @moduledoc "Assigns of the algorithm page derived from the algorithm and its input."
  import Phoenix.Component, only: [assign: 2]

  alias Subcipher.Algorithms
  alias Subcipher.Algorithms.Algorithm
  alias SubcipherWeb.AlgorithmLive.Steps.Summaries

  @doc "Shows `algorithm` after a change: title, steps and trace."
  def reload(socket, algorithm) do
    socket
    |> assign(
      algorithm: algorithm,
      page_title: algorithm.title,
      steps: Summaries.describe(algorithm)
    )
    |> assign_trace()
  end

  @doc "The text (or symbols) after each step, for the current mode and input."
  def assign_trace(socket) do
    %{algorithm: algorithm, mode: mode, texts: texts, symbols: symbols} = socket.assigns

    trace =
      case mode do
        "encode" ->
          Algorithms.encode(algorithm, texts["encode"])

        "decode" ->
          if Algorithm.pictures?(algorithm),
            do: Algorithms.decode(algorithm, symbols),
            else: Algorithms.decode(algorithm, texts["decode"])
      end

    assign(socket, trace: trace)
  end
end
