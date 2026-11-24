defmodule SubcipherWeb.Components.RangeField do
  @moduledoc "An integer parameter as a slider; its maximum can depend on the step's input."
  use SubcipherWeb, :html

  import SubcipherWeb.Components.FieldErrors

  attr :field, :map, required: true, doc: "a cipher field spec"
  attr :form_field, Phoenix.HTML.FormField, required: true
  attr :step_id, :integer, required: true
  attr :input, :string, required: true, doc: "the step's input text"
  attr :params, :map, default: %{}, doc: "the step's current (valid) parameters"

  def range_field(assigns) do
    %{field: field, input: input} = assigns
    max = if is_function(field[:max], 1), do: field.max.(input), else: field[:max]

    value =
      case assigns.form_field.value do
        nil -> if is_function(field[:auto], 1), do: field.auto.(input), else: field[:min]
        "" -> field[:min]
        value -> value
      end

    assigns = assign(assigns, max: max, value: min(to_integer(value), max))

    ~H"""
    <div class="max-w-sm space-y-1">
      <label for={@form_field.id} class="flex items-center justify-between text-sm font-medium">
        {@field.label}
        <span id={"#{@form_field.id}-value"} class="badge badge-sm badge-primary tabular-nums">
          {@value}
        </span>
      </label>
      <input
        type="range"
        id={@form_field.id}
        name={@form_field.name}
        min={@field[:min]}
        max={@max}
        value={@value}
        step="1"
        disabled={@max == @field[:min]}
        phx-debounce="100"
        class="range range-primary range-sm w-full"
      />
      <div class="flex justify-between text-[10px] text-base-content/50 tabular-nums">
        <span>{@field[:min]}</span><span>{@max}</span>
      </div>
      <p :if={@field[:help]} class="text-xs text-base-content/60">{@field.help}</p>
      <.field_errors form_field={@form_field} />
    </div>
    """
  end

  defp to_integer(value) when is_integer(value), do: value

  defp to_integer(value) do
    case Integer.parse(to_string(value)) do
      {i, _} -> i
      :error -> 0
    end
  end
end
