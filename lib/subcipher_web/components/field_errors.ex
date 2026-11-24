defmodule SubcipherWeb.Components.FieldErrors do
  @moduledoc "The errors of a form field."
  use SubcipherWeb, :html

  attr :form_field, Phoenix.HTML.FormField, required: true

  def field_errors(assigns) do
    ~H"""
    <p :for={msg <- Enum.map(@form_field.errors, &translate_error/1)} class="mt-1 text-sm text-error">
      {msg}
    </p>
    """
  end
end
