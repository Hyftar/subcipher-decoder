defmodule SubcipherWeb.AlgorithmLive.Input do
  @moduledoc """
  What an algorithm encodes or decodes: typed text, or symbols composed
  with the keyboard of its symbol key (decoding a pictures algorithm).
  """
  use SubcipherWeb, :html

  alias Subcipher.Algorithms.Algorithm

  import SubcipherWeb.AlgorithmLive.Input.SymbolKeyboard

  attr :algorithm, :any, required: true
  attr :mode, :string, required: true, doc: "\"encode\" or \"decode\""
  attr :text, :string, required: true, doc: "the text typed for this mode"
  attr :symbols, :list, required: true, doc: "the symbols composed with the keyboard"

  def algorithm_input(assigns) do
    ~H"""
    <section id="algorithm-input" class="space-y-2">
      <%= if @mode == "decode" and Algorithm.pictures?(@algorithm) do %>
        <.symbol_keyboard algorithm={@algorithm} symbols={@symbols} />
      <% else %>
        <.form for={%{}} id="text-form" phx-change="input" phx-submit="input">
          <label for="algorithm-text" class="block text-sm font-medium mb-1">
            {if @mode == "encode", do: "Plain text to encode", else: "Cipher text to decode"}
          </label>
          <textarea
            id="algorithm-text"
            name="text"
            rows="4"
            phx-debounce="250"
            spellcheck="false"
            placeholder={if @mode == "encode", do: "Type a message", else: "Paste the cipher text"}
            class="w-full rounded-lg border border-base-300 bg-base-200/50 p-3 font-mono text-lg leading-relaxed tracking-wider focus:outline-none focus:ring-2 focus:ring-primary/40"
          >{Phoenix.HTML.Form.normalize_value("textarea", @text)}</textarea>
        </.form>
      <% end %>
    </section>
    """
  end
end
