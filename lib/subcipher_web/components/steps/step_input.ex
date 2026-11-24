defmodule SubcipherWeb.Components.StepInput do
  @moduledoc """
  What a step decodes: the cipher text, editable (first step of a text
  puzzle), or the output of the previous step.
  """
  use SubcipherWeb, :html

  attr :number, :integer, required: true, doc: "displayed step number"
  attr :step, :any, required: true
  attr :input, :string, required: true
  attr :input_form, :any, default: nil, doc: "editable puzzle input (first step of a text puzzle)"

  def step_input(assigns) do
    ~H"""
    <div class="space-y-1.5">
      <h3 class="text-xs font-semibold uppercase tracking-wider text-base-content/50">
        {if @input_form, do: "Cipher text", else: "Input · output of step #{@number - 1}"}
      </h3>
      <.form
        :if={@input_form}
        for={@input_form}
        id="input-form"
        phx-change="update_input"
        phx-submit="update_input"
      >
        <textarea
          id="input-text"
          name={@input_form[:input_text].name}
          rows="5"
          phx-debounce="400"
          spellcheck="false"
          placeholder="Paste the cipher text here"
          class="w-full rounded-lg border border-base-300 bg-base-200/50 p-3 font-mono text-lg leading-relaxed tracking-wider focus:outline-none focus:ring-2 focus:ring-primary/40"
        >{Phoenix.HTML.Form.normalize_value("textarea", @input_form[:input_text].value)}</textarea>
      </.form>
      <pre
        :if={!@input_form}
        id={"step-input-#{@step.id}"}
        class="max-h-48 overflow-y-auto rounded-lg border border-dashed border-base-300 p-3 font-mono text-base text-base-content/70 whitespace-pre-wrap break-words tracking-wider"
      >{@input}</pre>
    </div>
    """
  end
end
