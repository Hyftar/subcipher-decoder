defmodule SubcipherWeb.AlgorithmLive.Trace.ColourChoice do
  @moduledoc "A colour of the symbol image: the detected one, or one chosen with the picker."
  use SubcipherWeb, :html

  attr :field, :string, required: true
  attr :label, :string, required: true
  attr :value, :string, required: true, doc: "\"auto\" or a #rrggbb colour"
  attr :detected, :any, required: true
  attr :title, :string, required: true
  attr :disabled, :boolean, default: false

  def colour_choice(assigns) do
    ~H"""
    <div class={["flex items-center gap-2 transition-opacity", @disabled && "opacity-40"]}>
      <span class="text-base-content/70">{@label}</span>
      <button
        type="button"
        id={"#{@field}-auto"}
        phx-click="image_auto"
        phx-value-colour={@field}
        disabled={@disabled}
        class={["btn btn-sm", @value == "auto" && "btn-primary"]}
        aria-pressed={to_string(@value == "auto")}
        title={@title}
      >
        <span
          class="inline-block size-4 rounded-sm ring-1 ring-base-content/30"
          style={"background: #{@detected || "transparent"}"}
        ></span>
        Detected
      </button>
      <input
        type="color"
        id={"#{@field}-color"}
        name={@field}
        value={if @value == "auto", do: @detected || "#ffffff", else: @value}
        disabled={@disabled}
        class="size-8 cursor-pointer rounded border border-base-300 bg-transparent disabled:cursor-not-allowed"
        aria-label={"#{@label} colour"}
        title={"Choose the #{String.downcase(@label)} colour"}
      />
      <span :if={@value != "auto"} class="font-mono text-xs">{@value}</span>
    </div>
    """
  end
end
