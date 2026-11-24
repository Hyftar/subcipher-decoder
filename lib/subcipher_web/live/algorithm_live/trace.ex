defmodule SubcipherWeb.AlgorithmLive.Trace do
  @moduledoc "The text (or symbols) after each step of an algorithm."
  use SubcipherWeb, :html

  import SubcipherWeb.Components.Output
  import SubcipherWeb.AlgorithmLive.Trace.SymbolImage

  alias SubcipherWeb.AlgorithmLive.Trace.ImageSpec

  attr :algorithm, :any, required: true
  attr :mode, :string, required: true, doc: "\"encode\" or \"decode\""
  attr :trace, :list, required: true, doc: "Subcipher.Algorithms.encode/2 or decode/2"
  attr :image, :map, required: true, doc: "the options of the symbol image"
  attr :detected, :map, required: true, doc: "the colours detected in the glyphs"

  def trace(assigns) do
    ~H"""
    <section id="trace" class="space-y-2">
      <h2 class="text-xs font-semibold uppercase tracking-wider text-base-content/50">
        {if @mode == "encode", do: "Encoding, step by step", else: "Decoding, step by step"}
      </h2>
      <ol class="space-y-0">
        <li :for={{stage, i} <- Enum.with_index(@trace)} id={"stage-#{i}"}>
          <div
            :if={i > 0}
            class="flex justify-center py-1 text-base-content/30"
            aria-hidden="true"
          >
            <.icon name="hero-arrow-down" class="size-4" />
          </div>
          <div class={[
            "rounded-xl border p-3 space-y-2",
            if(i == length(@trace) - 1,
              do: "border-primary/50 bg-primary/5",
              else: "border-base-300 bg-base-100"
            )
          ]}>
            <p class="text-xs font-semibold uppercase tracking-wider text-base-content/60">
              {stage.label}
            </p>
            <%= cond do %>
              <% stage.kind == :symbols and not ImageSpec.drawable?(stage.value) -> %>
                <p id="symbol-image-empty" class="text-sm text-base-content/50">
                  {if @mode == "encode",
                    do: "Type a message to see it written in symbols.",
                    else: "Click the symbols of the key to write the cipher text."}
                </p>
              <% stage.kind == :symbols -> %>
                <.symbol_image
                  algorithm={@algorithm}
                  tokens={stage.value}
                  options={@image}
                  detected={@detected}
                  filename={
                    "#{@algorithm.title} - #{if @mode == "encode", do: "encoded", else: "cipher"}"
                  }
                />
              <% true -> %>
                <.output id={"stage-text-#{i}"} text={stage.value} />
            <% end %>
          </div>
        </li>
      </ol>
    </section>
    """
  end
end
