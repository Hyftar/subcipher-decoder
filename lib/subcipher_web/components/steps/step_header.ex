defmodule SubcipherWeb.Components.StepHeader do
  @moduledoc """
  The top of a step card: its number, its cipher (changing it resets the
  settings), moving and removing the step, and what the cipher does.
  """
  use SubcipherWeb, :html

  alias Subcipher.Steps

  import SubcipherWeb.Components.OsrsUsage

  attr :number, :integer, required: true, doc: "displayed step number"
  attr :step, :any, required: true
  attr :cipher, :atom, required: true
  attr :can_move_up, :boolean, required: true
  attr :can_move_down, :boolean, required: true
  attr :can_delete, :boolean, required: true

  def step_header(assigns) do
    assigns = assign(assigns, type_form: to_form(%{"type" => assigns.step.type}, as: :step_type))

    ~H"""
    <div class="space-y-2">
      <div class="flex flex-wrap items-center gap-3">
        <span class="grid place-items-center size-8 rounded-full bg-primary text-primary-content text-sm font-semibold">
          {@number}
        </span>
        <.form
          for={@type_form}
          id={"step-type-form-#{@step.id}"}
          phx-change="change_step_type"
          class="flex-1 min-w-48"
        >
          <input type="hidden" name="step_id" value={@step.id} />
          <label class="sr-only" for={"step-type-#{@step.id}"}>Cipher</label>
          <select
            id={"step-type-#{@step.id}"}
            name="type"
            class="select select-sm font-semibold w-auto"
            title="Changing the cipher resets the settings of this step"
          >
            <option
              :for={cipher <- Steps.ciphers()}
              value={cipher.type()}
              selected={cipher.type() == @step.type}
            >
              {cipher.name()}
            </option>
          </select>
        </.form>
        <div class="flex items-center">
          <button
            type="button"
            id={"move-step-up-#{@step.id}"}
            class="btn btn-ghost btn-square"
            phx-click="move_step"
            phx-value-id={@step.id}
            phx-value-direction="up"
            disabled={!@can_move_up}
            aria-label="Move step earlier"
            title="Move earlier"
          >
            <.icon name="hero-arrow-left" class="size-5" />
          </button>
          <button
            type="button"
            id={"move-step-down-#{@step.id}"}
            class="btn btn-ghost btn-square"
            phx-click="move_step"
            phx-value-id={@step.id}
            phx-value-direction="down"
            disabled={!@can_move_down}
            aria-label="Move step later"
            title="Move later"
          >
            <.icon name="hero-arrow-right" class="size-5" />
          </button>
          <button
            type="button"
            id={"delete-step-#{@step.id}"}
            class="btn btn-ghost btn-square"
            phx-click="delete_step"
            phx-value-id={@step.id}
            disabled={!@can_delete}
            data-confirm={"Remove step #{@number} (#{@cipher.name()})?"}
            aria-label="Remove step"
            title={if @can_delete, do: "Remove step", else: "A text cipher needs at least one step"}
          >
            <.icon name="hero-trash" class="size-5" />
          </button>
        </div>
      </div>
      <div class="space-y-1">
        <p class="text-sm text-base-content/60">{@cipher.description()}</p>
        <.osrs_usage cipher={@cipher} />
      </div>
    </div>
    """
  end
end
