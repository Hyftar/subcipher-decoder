defmodule SubcipherWeb.Components.OsrsUsage do
  @moduledoc "Where a cipher is used in Old School RuneScape, if known."
  use SubcipherWeb, :html

  alias Subcipher.Steps

  attr :cipher, :atom, required: true
  attr :class, :string, default: nil

  @doc "Where the cipher is used in Old School RuneScape, if known."
  def osrs_usage(assigns) do
    assigns =
      assign(assigns,
        usage:
          if(Steps.implements?(assigns.cipher, :osrs_usage, 0), do: assigns.cipher.osrs_usage())
      )

    ~H"""
    <p :if={@usage} class={["flex items-center gap-1.5 text-xs text-base-content/60", @class]}>
      <span class="shrink-0 rounded bg-warning/15 px-1 py-px text-[10px] font-bold tracking-wide text-warning">
        OSRS
      </span>
      <span>{@usage}</span>
    </p>
    """
  end
end
