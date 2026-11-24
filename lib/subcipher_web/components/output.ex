defmodule SubcipherWeb.Components.Output do
  @moduledoc "A text output, with a copy button when it is not empty."
  use SubcipherWeb, :html

  attr :id, :string, required: true
  attr :text, :string, required: true
  attr :class, :string, default: nil

  def output(assigns) do
    ~H"""
    <div class={["relative group rounded-lg bg-base-200/50", @class]}>
      <button
        :if={String.trim(@text) != ""}
        type="button"
        id={"#{@id}-copy"}
        class="absolute top-2 right-2 btn btn-ghost btn-sm btn-square opacity-60 group-hover:opacity-100"
        phx-click={JS.dispatch("phx:copy", to: "##{@id}")}
        aria-label="Copy"
        title="Copy"
      >
        <.icon name="hero-clipboard" class="size-5" />
      </button>
      <pre
        id={@id}
        class="min-h-12 p-3 pr-12 font-mono text-lg whitespace-pre-wrap break-words leading-relaxed tracking-wider"
      >{@text}</pre>
    </div>
    """
  end
end
