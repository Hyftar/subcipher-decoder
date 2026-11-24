defmodule SubcipherWeb.AlgorithmLive.Input.SymbolKeyboard do
  @moduledoc """
  Composes symbol cipher text by clicking the symbols of the key (each with
  the letter it stands for), plus space, new line, backspace and clear.
  """
  use SubcipherWeb, :html

  import SubcipherWeb.AlgorithmLive.{KeyGlyph, Input.SymbolsView}

  attr :algorithm, :any, required: true
  attr :symbols, :list, required: true

  def symbol_keyboard(assigns) do
    assigns =
      assign(assigns,
        sorted_symbol_key:
          assigns.algorithm.symbol_key
          |> Enum.with_index()
          |> Enum.sort_by(fn {entry, _i} -> key_order(entry["letter"]) end)
      )

    ~H"""
    <div class="space-y-2">
      <p class="text-sm font-medium">Cipher symbols to decode</p>
      <div
        id="composed-symbols"
        class="min-h-14 rounded-lg border border-base-300 bg-base-200/50 p-2"
      >
        <.symbols_view algorithm={@algorithm} tokens={@symbols} id="composed" />
        <p :if={@symbols == []} class="text-sm text-base-content/50 p-1">
          Click the symbols below to write the cipher text.
        </p>
      </div>
      <div id="symbol-keyboard" class="flex flex-wrap justify-center gap-2">
        <button
          :for={{entry, i} <- @sorted_symbol_key}
          type="button"
          id={"key-#{i}"}
          phx-click="add_symbol"
          phx-value-index={i}
          class="group flex flex-col items-center justify-end gap-1 min-w-12 rounded-lg border border-base-300 bg-base-100 px-1.5 pt-1.5 pb-1 transition hover:border-primary hover:bg-primary/5 hover:-translate-y-0.5 hover:shadow-sm active:translate-y-0"
          aria-label={"Symbol #{i + 1} (#{entry["letter"]})"}
          title={entry["letter"]}
        >
          <.key_glyph algorithm={@algorithm} entry={entry} />
          <span
            id={"key-#{i}-letter"}
            class="font-mono text-sm font-semibold uppercase leading-none text-base-content/60 group-hover:text-primary transition-colors"
          >
            {entry["letter"]}
          </span>
        </button>
      </div>
      <div class="flex flex-wrap gap-2">
        <button
          type="button"
          id="key-space"
          class="btn"
          phx-click="add_char"
          phx-value-char="space"
        >
          Space
        </button>
        <button
          type="button"
          id="key-newline"
          class="btn"
          phx-click="add_char"
          phx-value-char="newline"
        >
          New line
        </button>
        <button
          type="button"
          id="key-backspace"
          class="btn"
          phx-click="backspace"
          aria-label="Delete the last symbol"
        >
          <.icon name="hero-backspace" class="size-5" />
        </button>
        <button type="button" id="key-clear" class="btn btn-ghost" phx-click="clear">
          Clear
        </button>
      </div>
    </div>
    """
  end

  defp key_order(text) when is_binary(text),
    do: {if(text =~ ~r/^[A-Z]+$/, do: 0, else: 1), text}

  defp key_order(_), do: {2, ""}
end
