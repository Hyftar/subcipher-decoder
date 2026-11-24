defmodule SubcipherWeb.Components.SuggestionCard do
  @moduledoc "A suggestion: why it is suggested, a preview, and \"Use\" to apply it."
  use SubcipherWeb, :html

  attr :id, :string, required: true
  attr :use_id, :string, required: true
  attr :suggestion, :map, required: true

  def suggestion_card(assigns) do
    ~H"""
    <li
      id={@id}
      class={[
        "min-w-0 rounded-xl border p-3 transition-colors bg-base-100",
        if(@suggestion.applied,
          do: "border-success/50 bg-success/5",
          else: "border-base-300 hover:border-primary/50"
        )
      ]}
    >
      <div class="flex flex-wrap items-center gap-2">
        <span class="font-semibold text-sm">{@suggestion.label}</span>
        <span :if={@suggestion.applied} class="badge badge-sm badge-success badge-soft">
          <.icon name="hero-check" class="size-3" /> Applied
        </span>
        <button
          :if={!@suggestion.applied}
          type="button"
          id={@use_id}
          class="btn btn-primary btn-soft btn-sm ml-auto"
          phx-click={@suggestion.use}
        >
          Use
        </button>
      </div>
      <p class="mt-1 text-sm text-base-content/70">{@suggestion.reason}</p>
      <p class="mt-1.5 font-mono text-sm truncate text-base-content/90" title={@suggestion.preview}>
        {@suggestion.preview}
      </p>
    </li>
    """
  end
end
