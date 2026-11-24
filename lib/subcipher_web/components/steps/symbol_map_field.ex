defmodule SubcipherWeb.Components.SymbolMapField do
  @moduledoc "One input per distinct character of the step's input, most frequent first."
  use SubcipherWeb, :html

  alias Subcipher.Steps.Alphabet
  alias Subcipher.Steps.Ciphers.SymbolSubstitution

  import SubcipherWeb.Components.FieldErrors

  attr :field, :map, required: true, doc: "a cipher field spec"
  attr :form_field, Phoenix.HTML.FormField, required: true
  attr :step_id, :integer, required: true
  attr :input, :string, required: true, doc: "the step's input text"
  attr :params, :map, default: %{}, doc: "the step's current (valid) parameters"

  def symbol_map_field(assigns) do
    assigns =
      assign(assigns,
        mapping: assigns.form_field.value || %{},
        symbols: Alphabet.symbol_frequencies(assigns.input)
      )

    ~H"""
    <fieldset>
      <legend class="text-sm font-medium mb-1">{@field.label}</legend>
      <p :if={@symbols == []} class="text-sm text-base-content/60">
        No symbols in the input yet.
      </p>
      <div class="grid grid-cols-[repeat(auto-fill,minmax(4rem,1fr))] gap-1.5">
        <label
          :for={{{symbol, count}, i} <- Enum.with_index(@symbols)}
          for={"step-#{@step_id}-symbol-#{i}"}
          class="flex flex-col items-center rounded-md border border-base-300 bg-base-100 px-1 pt-1 pb-1.5"
        >
          <span class="font-mono text-xl leading-7">{symbol}</span>
          <span class="text-[10px] leading-3 text-base-content/50">×{count}</span>
          <input
            type="text"
            id={"step-#{@step_id}-symbol-#{i}"}
            name={"#{@form_field.name}[#{SymbolSubstitution.form_key(symbol)}]"}
            value={Map.get(@mapping, symbol)}
            maxlength="3"
            autocomplete="off"
            spellcheck="false"
            phx-debounce="150"
            aria-label={"Letter for #{symbol}"}
            class="mt-1 w-11 h-7 rounded border border-base-300 bg-base-100 text-center font-mono uppercase text-primary focus:outline-none focus:ring-2 focus:ring-primary/40"
          />
        </label>
      </div>
      <.field_errors form_field={@form_field} />
    </fieldset>
    """
  end
end
