defmodule SubcipherWeb.AlgorithmLive.Steps.EditorSteps do
  @moduledoc """
  What the steps editor shows for each stored step of an algorithm: its
  cipher, settings form and the text it decodes.
  """
  import Phoenix.Component, only: [to_form: 2]

  alias Subcipher.{Algorithms, Steps}
  alias Subcipher.Algorithms.Algorithm
  alias Subcipher.Steps.Step

  @doc """
  The editor's entries, by step: index, number, cipher, params, input (from
  the decode trace, so settings that depend on the input, like the symbols
  of a symbol substitution, can be set) and settings form (the invalid one
  being edited, if any).
  """
  def build(assigns) do
    %{algorithm: algorithm, texts: texts, symbols: symbols, step_forms: forms} = assigns

    {inputs, offset} =
      if Algorithm.pictures?(algorithm),
        do: {Algorithms.decode(algorithm, symbols), 1},
        else: {Algorithms.decode(algorithm, texts["decode"]), 0}

    for {%{"type" => type, "params" => params}, index} <- Enum.with_index(algorithm.steps) do
      step = %Step{type: type, params: params}

      %{
        index: index,
        number: index + offset + 1,
        cipher: Steps.cipher!(type),
        params: Steps.params(step),
        input: Enum.at(inputs, index + offset).value,
        form:
          forms[index] ||
            to_form(Steps.params_changeset(type, params),
              as: :step,
              id: "algorithm-step-form-#{index}"
            )
      }
    end
  end
end
