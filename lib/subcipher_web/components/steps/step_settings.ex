defmodule SubcipherWeb.Components.StepSettings do
  @moduledoc """
  The settings form of a step, generated from its cipher's `fields/0` (see
  `SubcipherWeb.Components.ParamField`), with the cipher's summary of them.
  """
  use SubcipherWeb, :html

  alias Subcipher.Steps

  import SubcipherWeb.Components.ParamField

  attr :step, :any, required: true
  attr :cipher, :atom, required: true
  attr :result, :map, required: true, doc: "an entry of Subcipher.Steps.run/2"
  attr :form, :any, required: true

  def step_settings(assigns) do
    assigns = assign(assigns, summary: summary(assigns.cipher, assigns.result.params))

    ~H"""
    <div class="space-y-2">
      <h3 class="text-xs font-semibold uppercase tracking-wider text-base-content/50">
        Settings
      </h3>
      <.form
        for={@form}
        id={"step-form-#{@step.id}"}
        phx-change="update_step"
        phx-submit="update_step"
        class="space-y-2"
      >
        <input type="hidden" name="step_id" value={@step.id} />
        <.param_field
          :for={field <- @cipher.fields()}
          field={field}
          form_field={@form[field.name]}
          step_id={@step.id}
          input={@result.input}
          params={@result.params}
        />
      </.form>
      <pre
        :if={@summary}
        id={"step-summary-#{@step.id}"}
        class="text-xs font-mono text-base-content/60 whitespace-pre-wrap"
      >{@summary}</pre>
    </div>
    """
  end

  defp summary(cipher, params) do
    if Steps.implements?(cipher, :summary, 1), do: cipher.summary(params)
  end
end
