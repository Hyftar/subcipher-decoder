defmodule SubcipherWeb.Components.StepNav do
  @moduledoc "The decoding steps of a puzzle, as connected circles."
  use SubcipherWeb, :html

  attr :puzzle, :any, required: true
  attr :nodes, :list, required: true, doc: "[%{number:, label:, icon:}] in order"
  attr :selected, :any, required: true, doc: "number of the shown step, or :new"
  attr :owner, :boolean, default: true, doc: "the current user may add steps"

  @doc "Steps as connected circles; for the owner, the last one adds a step."
  def step_nav(assigns) do
    ~H"""
    <nav id="step-nav" aria-label="Decoding steps" class="overflow-x-auto">
      <ol class="flex items-start min-w-max px-1 pt-1 pb-2">
        <%= for node <- @nodes do %>
          <li class="flex flex-col items-center gap-1.5 w-24">
            <.link
              patch={~p"/puzzles/#{@puzzle}?step=#{node.number}"}
              id={"step-nav-#{node.number}"}
              aria-current={if node.number == @selected, do: "step"}
              title={node.label}
              class={[
                "relative grid place-items-center size-10 rounded-full border-2 font-semibold transition-all",
                if(node.number == @selected,
                  do:
                    "bg-primary border-primary text-primary-content ring-4 ring-primary/20 scale-105",
                  else: "bg-base-100 border-base-300 hover:border-primary hover:text-primary"
                )
              ]}
            >
              {node.number}
              <span
                :if={node[:icon]}
                class="absolute -bottom-1 -right-1 grid place-items-center size-4 rounded-full bg-base-100 text-base-content/60 ring-1 ring-base-300"
              >
                <.icon name={node.icon} class="size-3" />
              </span>
            </.link>
            <span class={[
              "text-xs text-center leading-tight px-1 line-clamp-2",
              if(node.number == @selected,
                do: "font-semibold text-base-content",
                else: "text-base-content/60"
              )
            ]}>
              {node.label}
            </span>
          </li>
          <li
            :if={@owner or node != List.last(@nodes)}
            aria-hidden="true"
            class="flex-1 min-w-6 h-0.5 mt-5 -mx-7 bg-base-300 rounded-full"
          >
          </li>
        <% end %>
        <li :if={@owner} class="flex flex-col items-center gap-1.5 w-24">
          <.link
            patch={~p"/puzzles/#{@puzzle}?step=new"}
            id="step-nav-new"
            aria-current={if @selected == :new, do: "step"}
            title="Add a step"
            class={[
              "grid place-items-center size-10 rounded-full border-2 border-dashed transition-all",
              if(@selected == :new,
                do: "border-primary bg-primary/10 text-primary ring-4 ring-primary/20",
                else: "border-base-300 text-base-content/50 hover:border-primary hover:text-primary"
              )
            ]}
          >
            <.icon name="hero-plus" class="size-5" />
          </.link>
          <span class="text-xs text-center text-base-content/60">Add step</span>
        </li>
      </ol>
    </nav>
    """
  end
end
