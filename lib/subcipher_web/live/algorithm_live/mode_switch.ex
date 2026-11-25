defmodule SubcipherWeb.AlgorithmLive.ModeSwitch do
  @moduledoc "The encode / decode tabs of an algorithm."
  use SubcipherWeb, :html

  attr :path, :string, required: true, doc: "the page's path (the mode is patched onto it)"
  attr :mode, :string, required: true, doc: "\"encode\" or \"decode\""

  def mode_switch(assigns) do
    ~H"""
    <div
      role="tablist"
      id="mode-switch"
      class="inline-flex rounded-xl bg-base-200 p-1"
    >
      <.link
        :for={
          {mode, label, icon} <- [
            {"encode", "Encode", "hero-lock-closed"},
            {"decode", "Decode", "hero-lock-open"}
          ]
        }
        patch={"#{@path}?mode=#{mode}"}
        role="tab"
        id={"mode-#{mode}"}
        aria-selected={to_string(@mode == mode)}
        class={[
          "flex items-center gap-2 rounded-lg px-5 py-2 font-medium transition",
          if(@mode == mode,
            do: "bg-base-100 shadow-sm",
            else: "text-base-content/60 hover:text-base-content"
          )
        ]}
      >
        <.icon name={icon} class="size-5" /> {label}
      </.link>
    </div>
    """
  end
end
