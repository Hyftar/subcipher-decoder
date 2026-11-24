defmodule SubcipherWeb.AlgorithmLive.Steps.EditorStep do
  @moduledoc "A step of an algorithm, editable: its cipher, settings and place."
  use SubcipherWeb, :html

  alias Subcipher.Algorithms.Algorithm

  import SubcipherWeb.Components.ParamField

  attr :step, :map, required: true, doc: "see SubcipherWeb.AlgorithmLive.Steps.EditorSteps"
  attr :count, :integer, required: true, doc: "number of steps"
  attr :algorithm, :any, required: true
  attr :ciphers, :list, required: true, doc: "the ciphers offered"

  def editor_step(assigns) do
    ~H"""
    <section
      id={"editor-step-#{@step.index}"}
      class="rounded-2xl border border-base-300 bg-base-100 p-4 sm:p-6 space-y-4 transition-shadow hover:shadow-sm"
    >
      <div class="flex flex-wrap items-center gap-3">
        <span class="grid place-items-center size-8 rounded-full bg-primary text-primary-content text-sm font-semibold">
          {@step.number}
        </span>
        <form
          id={"editor-step-type-#{@step.index}"}
          phx-change="change_step_type"
          class="flex-1 min-w-48"
        >
          <input type="hidden" name="index" value={@step.index} />
          <select
            id={"editor-step-cipher-#{@step.index}"}
            name="type"
            class="select select-sm font-semibold w-auto"
            aria-label="Cipher"
            title="Changing the cipher resets the settings of this step"
          >
            <option
              :for={cipher <- @ciphers}
              value={cipher.type()}
              selected={cipher == @step.cipher}
            >
              {cipher.name()}
            </option>
          </select>
        </form>
        <div class="flex items-center">
          <button
            :for={
              {direction, icon, label, enabled} <- [
                {"up", "hero-arrow-up", "Move earlier", @step.index > 0},
                {"down", "hero-arrow-down", "Move later", @step.index < @count - 1}
              ]
            }
            type="button"
            id={"editor-move-#{direction}-#{@step.index}"}
            class="btn btn-ghost btn-sm btn-square"
            phx-click="move_step"
            phx-value-index={@step.index}
            phx-value-direction={direction}
            disabled={!enabled}
            aria-label={label}
            title={label}
          >
            <.icon name={icon} class="size-4" />
          </button>
          <button
            type="button"
            id={"editor-delete-#{@step.index}"}
            class="btn btn-ghost btn-square"
            phx-click="delete_step"
            phx-value-index={@step.index}
            disabled={@count == 1 and not Algorithm.pictures?(@algorithm)}
            data-confirm={"Remove step #{@step.number} (#{@step.cipher.name()})?"}
            aria-label="Remove step"
            title="Remove step"
          >
            <.icon name="hero-trash" class="size-5" />
          </button>
        </div>
      </div>
      <p class="-mt-2 text-sm text-base-content/60">{@step.cipher.description()}</p>

      <.form
        :if={@step.cipher.fields() != []}
        for={@step.form}
        id={"editor-step-form-#{@step.index}"}
        phx-change="update_step"
        phx-submit="update_step"
        class="space-y-2"
      >
        <input type="hidden" name="index" value={@step.index} />
        <.param_field
          :for={field <- @step.cipher.fields()}
          field={field}
          form_field={@step.form[field.name]}
          step_id={@step.index}
          input={@step.input}
          params={@step.params}
        />
      </.form>
      <p :if={@step.cipher.fields() == []} class="text-sm text-base-content/50 italic">
        No settings.
      </p>
    </section>
    """
  end
end
