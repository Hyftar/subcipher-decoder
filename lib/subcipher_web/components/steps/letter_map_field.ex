defmodule SubcipherWeb.Components.LetterMapField do
  @moduledoc """
  One small input per cipher letter, with how often it appears in the
  step's input as a hint.
  """
  use SubcipherWeb, :html

  alias Subcipher.Steps.Alphabet

  import SubcipherWeb.Components.FieldErrors

  attr :field, :map, required: true, doc: "a cipher field spec"
  attr :form_field, Phoenix.HTML.FormField, required: true
  attr :step_id, :integer, required: true
  attr :input, :string, required: true, doc: "the step's input text"
  attr :params, :map, default: %{}, doc: "the step's current (valid) parameters"

  def letter_map_field(assigns) do
    assigns =
      assign(assigns,
        mapping: assigns.form_field.value || %{},
        frequencies: Alphabet.frequencies(assigns.input)
      )

    ~H"""
    <fieldset>
      <legend class="text-sm font-medium mb-1">{@field.label}</legend>
      <div class="grid grid-cols-7 sm:grid-cols-13 gap-1.5">
        <label
          :for={letter <- Alphabet.letters()}
          for={"step-#{@step_id}-map-#{letter}"}
          class={[
            "flex flex-col items-center rounded-md border px-1 pt-1 pb-1.5 transition-colors",
            if(Map.get(@frequencies, letter),
              do: "border-base-300 bg-base-100",
              else: "border-transparent bg-base-200/40 opacity-60"
            )
          ]}
        >
          <span class="font-mono text-sm font-semibold">{letter}</span>
          <span class="text-[10px] leading-3 text-base-content/50">
            ×{Map.get(@frequencies, letter, 0)}
          </span>
          <input
            type="text"
            id={"step-#{@step_id}-map-#{letter}"}
            name={"#{@form_field.name}[#{letter}]"}
            value={Map.get(@mapping, letter)}
            maxlength="1"
            autocomplete="off"
            spellcheck="false"
            phx-debounce="150"
            aria-label={"Plain letter for #{letter}"}
            class="mt-1 w-7 h-7 rounded border border-base-300 bg-base-100 text-center font-mono uppercase text-primary focus:outline-none focus:ring-2 focus:ring-primary/40"
          />
        </label>
      </div>
      <.field_errors form_field={@form_field} />
    </fieldset>
    """
  end
end
