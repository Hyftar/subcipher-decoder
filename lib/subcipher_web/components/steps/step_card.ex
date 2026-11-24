defmodule SubcipherWeb.Components.StepCard do
  @moduledoc """
  A decoding step of a puzzle: its cipher, input, settings, suggestions and
  output.

  Parameter forms are generated from each cipher's `fields/0` (see
  `SubcipherWeb.Components.ParamField`).
  """
  use SubcipherWeb, :html

  import SubcipherWeb.Components.{
    Output,
    StepHeader,
    StepInput,
    StepSettings,
    SuggestionsPanel
  }

  attr :number, :integer, required: true, doc: "displayed step number"
  attr :result, :map, required: true, doc: "an entry of Subcipher.Steps.run/2"
  attr :form, :any, required: true

  attr :solver_state, :any,
    default: nil,
    doc: "nil (no solver), :idle, :running, {:ok, suggestion} or {:error, message}"

  attr :suggestions, :any,
    default: nil,
    doc: "Subcipher.Steps.suggestions/3: a list, or nil when the cipher doesn't suggest"

  attr :can_move_up, :boolean, required: true
  attr :can_move_down, :boolean, required: true
  attr :can_delete, :boolean, required: true
  attr :input_form, :any, default: nil, doc: "editable puzzle input (first step of a text puzzle)"

  def step_card(assigns) do
    assigns = assign(assigns, step: assigns.result.step, cipher: assigns.result.cipher)

    ~H"""
    <section
      id={"step-#{@step.id}"}
      class="rounded-2xl border border-base-300 bg-base-100 p-4 sm:p-6 space-y-5"
    >
      <.step_header
        number={@number}
        step={@step}
        cipher={@cipher}
        can_move_up={@can_move_up}
        can_move_down={@can_move_down}
        can_delete={@can_delete}
      />
      <.step_input number={@number} step={@step} input={@result.input} input_form={@input_form} />
      <.step_settings
        :if={@cipher.fields() != []}
        step={@step}
        cipher={@cipher}
        result={@result}
        form={@form}
      />

      <.suggestions_panel
        :if={@suggestions || @solver_state}
        id={to_string(@step.id)}
        class="rounded-xl border border-base-300"
        suggestions={Enum.map(@suggestions || [], &Map.put(&1, :use, use_params(@step, &1)))}
        solver={
          @solver_state &&
            %{
              state: with_use(@solver_state, @step),
              start: JS.push("solve", value: %{target: @step.id}),
              help: Subcipher.Steps.solve_help(@cipher)
            }
        }
      />

      <div class="space-y-1.5">
        <h3 class="text-xs font-semibold uppercase tracking-wider text-base-content/50">Output</h3>
        <.output id={"step-output-#{@step.id}"} text={@result.output} />
      </div>
    </section>
    """
  end

  defp use_params(step, suggestion),
    do: JS.push("apply_suggestion", value: %{id: step.id, params: suggestion.params})

  defp with_use({:ok, solution}, step),
    do: solution |> Map.put(:use, use_params(step, solution)) |> wrap(:ok)

  defp with_use(state, _step), do: state
end
