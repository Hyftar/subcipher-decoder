defmodule SubcipherWeb.Components.ParamField do
  @moduledoc """
  The form field of a cipher parameter, from its spec in the cipher's
  `fields/0`: a new cipher type gets its form without touching this module,
  as long as it uses the existing field types (`:integer`, `:string`,
  `:select`, `:permutation`, `:letter_map`, `:symbol_map`).
  """
  use SubcipherWeb, :html

  alias SubcipherWeb.Components.{AnagramTiles, LetterMapField, RangeField, SymbolMapField}

  attr :field, :map, required: true, doc: "a cipher field spec"
  attr :form_field, Phoenix.HTML.FormField, required: true
  attr :step_id, :integer, required: true
  attr :input, :string, required: true, doc: "the step's input text"
  attr :params, :map, default: %{}, doc: "the step's current (valid) parameters"

  def param_field(%{field: %{type: :integer, control: :range}} = assigns),
    do: RangeField.range_field(assigns)

  def param_field(%{field: %{type: :integer}} = assigns) do
    ~H"""
    <div class="max-w-xs">
      <.input
        field={@form_field}
        type="number"
        label={@field.label}
        min={@field[:min]}
        max={@field[:max]}
        phx-debounce="200"
      />
      <p :if={@field[:help]} class="-mt-1 text-xs text-base-content/60">{@field.help}</p>
    </div>
    """
  end

  def param_field(%{field: %{type: :string}} = assigns) do
    ~H"""
    <div class="max-w-sm">
      <.input field={@form_field} type="text" label={@field.label} phx-debounce="300" />
      <p :if={@field[:help]} class="-mt-1 text-xs text-base-content/60">{@field.help}</p>
    </div>
    """
  end

  def param_field(%{field: %{type: :select}} = assigns) do
    ~H"""
    <div class="max-w-sm">
      <.input field={@form_field} type="select" label={@field.label} options={@field.options} />
      <p :if={@field[:help]} class="-mt-1 text-xs text-base-content/60">{@field.help}</p>
    </div>
    """
  end

  def param_field(%{field: %{type: :permutation}} = assigns),
    do: AnagramTiles.anagram_tiles(assigns)

  def param_field(%{field: %{type: :letter_map}} = assigns),
    do: LetterMapField.letter_map_field(assigns)

  def param_field(%{field: %{type: :symbol_map}} = assigns),
    do: SymbolMapField.symbol_map_field(assigns)
end
