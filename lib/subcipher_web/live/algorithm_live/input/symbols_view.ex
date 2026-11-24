defmodule SubcipherWeb.AlgorithmLive.Input.SymbolsView do
  @moduledoc "Symbol tokens drawn with the key's glyphs, lines and spaces kept."
  use SubcipherWeb, :html

  import SubcipherWeb.AlgorithmLive.KeyGlyph

  attr :algorithm, :any, required: true
  attr :tokens, :list, required: true
  attr :id, :string, required: true

  def symbols_view(assigns) do
    lines =
      Enum.chunk_by(assigns.tokens, &(&1 == {:char, "\n"}))
      |> Enum.reject(&(&1 == [{:char, "\n"}]))

    assigns = assign(assigns, lines: lines)

    ~H"""
    <div id={@id} class="space-y-2">
      <div :for={line <- @lines} class="flex flex-wrap items-end gap-1">
        <%= for token <- line do %>
          <%= case token do %>
            <% {:symbol, i} -> %>
              <.key_glyph algorithm={@algorithm} entry={Enum.at(@algorithm.symbol_key, i)} />
            <% {:char, " "} -> %>
              <span class="w-4" aria-hidden="true"></span>
            <% {:char, char} -> %>
              <span class="font-mono text-lg text-base-content/60">{char}</span>
            <% {:missing, letter} -> %>
              <span
                class="grid place-items-center h-9 min-w-7 rounded border border-dashed border-error/60 font-mono text-error"
                title={"No symbol for #{letter} in the key"}
              >
                {letter}
              </span>
          <% end %>
        <% end %>
      </div>
    </div>
    """
  end
end
